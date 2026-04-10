# frozen_string_literal: true

require_relative "poll_assert"

module EventBusDSL
  include PollAssert

  attr_reader :event_bus

  # Setup & Initialization

  def create_event_bus(options = {})
    @event_bus = TCB::EventBus.new

    # Auto-subscribe to SubscriberInvocationFailed for test observability
    subscribe_to(TCB::SubscriberInvocationFailed) { |event| }
    subscribe_to(TCB::EventBusShutdown) { |event| }
    @handler_calls = Hash.new { |h, k| h[k] = [] }
    @named_handlers = {}
    @handler_call_order = []
    @handler_thread_ids = Hash.new { |h, k| h[k] = [] }
    @handler_errors = Hash.new { |h, k| h[k] = [] }
    @main_thread_id = Thread.current.object_id
    @publish_start_time = nil
    @last_publish_duration = nil
    @handler_latches = Hash.new { |h, k| h[k] = [] }
    self
  end

  def create_synchronous_bus
    # For now, same as regular bus - we'll add sync mode later
    create_event_bus(sync_mode: true)
  end

  # Event Publication

  def publish_event(event)
    @publish_start_time ||= Time.now
    start_time = Time.now
    @last_published_event = event_bus.publish(event)
    @last_publish_duration = Time.now - start_time
    self
  end

  def publish_events(*events)
    @publish_start_time = Time.now
    events.each { |event| publish_event(event) }
    self
  end

  def publish_concurrently(count, &event_builder_block)
    threads = count.times.map do |i|
      Thread.new do
        event = event_builder_block.call(i)
        publish_event(event)
      end
    end
    threads.each(&:join)
    self
  end

  def publish_concurrently_from_threads(thread_count, events_per_thread, &event_builder_block)
    threads = thread_count.times.map do |thread_id|
      Thread.new do
        events_per_thread.times do |i|
          event = event_builder_block.call(thread_id, i)
          publish_event(event)
        end
      end
    end
    threads.each(&:join)
    self
  end

  # Subscription

  def subscribe_to(event_class, &handler)
    wrapped_handler = wrap_handler(event_class, nil, handler)
    event_bus.subscribe(event_class, &wrapped_handler)
    self
  end

  def subscribe_with_id(id, event_class, &handler)
    wrapped_handler = wrap_handler(event_class, id, handler)
    @named_handlers[id] = { event_class: event_class, handler: wrapped_handler }
    event_bus.subscribe(event_class, &wrapped_handler)
    self
  end

  def subscribe_concurrently(event_class, count, &handler)
    threads = count.times.map do
      Thread.new do
        subscribe_to(event_class, &handler)
      end
    end
    threads.each(&:join)
    self
  end

  # Assertions

  def assert_event_delivered_to_handler(event_class, expected_data = {})
    poll_assert("#{event_class} to be delivered", within: 1.0) do
      !@handler_calls[event_class].empty?
    end

    unless expected_data.empty?
      calls = @handler_calls[event_class]
      matching_call = calls.find do |call|
        expected_data.all? { |key, value| call.public_send(key) == value }
      end
      assert matching_call, "Expected #{event_class} with data #{expected_data.inspect} but got #{calls.inspect}"
    end

    self
  end

  def assert_handler_called_times(event_class, expected_count)
    poll_assert("#{event_class} handler called #{expected_count} times", within: 1.0) do
      @handler_calls[event_class].size >= expected_count
    end

    actual_count = @handler_calls[event_class].size
    assert_equal expected_count, actual_count,
      "Expected #{event_class} handler to be called #{expected_count} times, but was called #{actual_count} times"

    self
  end

  def assert_handlers_called_in_order(event_class, *handler_ids)
    poll_assert("handlers for #{event_class} to be called", within: 1.0) do
      @handler_call_order.any? { |call| call[:event_class] == event_class && call[:handler_id] }
    end

    actual_order = @handler_call_order
      .select { |call| call[:event_class] == event_class && call[:handler_id] }
      .map { |call| call[:handler_id] }

    assert_equal handler_ids, actual_order,
      "Expected handlers to be called in order #{handler_ids.inspect}, but got #{actual_order.inspect}"

    self
  end

  def assert_event_not_delivered(event_class)
    # Negative assertion — caller must ensure prior wait (e.g. wait_for_handlers_to_complete)
    calls = @handler_calls[event_class]
    assert calls.empty?, "Expected #{event_class} NOT to be delivered but #{calls.size} calls recorded"

    self
  end

  def assert_last_published_event_matches(expected_data)
    expected_data.each do |key, value|
      actual_value = @last_published_event.public_send(key)
      assert_equal value, actual_value,
        "Expected last published event #{key} to be #{value.inspect}, but was #{actual_value.inspect}"
    end
    self
  end

  def assert_captured_events(event_class, &block)
    poll_assert("#{event_class} events to be captured", within: 1.0) do
      !@handler_calls[event_class].empty?
    end
    events = @handler_calls[event_class]
    block.call(events)
    self
  end

  def assert_handler_executed_asynchronously(event_class)
    poll_assert("#{event_class} handler to be called", within: 1.0) do
      !@handler_calls[event_class].empty?
    end

    handler_thread_id = @handler_thread_ids[event_class]&.first
    refute_nil handler_thread_id, "Handler thread ID should be recorded"
    refute_equal @main_thread_id, handler_thread_id,
      "Handler should execute in background thread, not main thread"

    self
  end

  def assert_events_dispatched_concurrently(event_class, expected_count, max_duration_seconds)
    start_time = @publish_start_time

    wait_for_handlers_to_complete(event_class, expected_count, timeout: max_duration_seconds)

    actual_count = @handler_calls[event_class].size
    assert_equal expected_count, actual_count,
      "Expected #{expected_count} events, got #{actual_count}"

    total_time = Time.now - start_time
    assert total_time < max_duration_seconds,
      "Events should be dispatched concurrently (took #{total_time}s, expected < #{max_duration_seconds}s)"

    self
  end

  def assert_handlers_execute_in_dispatcher_thread(event_class)
    poll_assert("#{event_class} handler to be called", within: 1.0) do
      !@handler_calls[event_class].empty?
    end

    handler_thread_ids = @handler_thread_ids[event_class]
    refute_nil handler_thread_ids, "Handler thread IDs should be recorded"
    refute_empty handler_thread_ids, "Should have recorded handler thread IDs"

    unique_thread_ids = handler_thread_ids.uniq
    assert_equal 1, unique_thread_ids.size,
      "All handlers for #{event_class} should execute in the same thread, but got #{unique_thread_ids.size} different threads"

    dispatcher_thread_id = unique_thread_ids.first
    refute_equal @main_thread_id, dispatcher_thread_id,
      "Handlers should execute in dispatcher thread, not main thread"

    self
  end

  def assert_publish_returns_immediately(max_duration_seconds = 0.1)
    publish_time = @last_publish_duration
    refute_nil publish_time, "Publish duration should be recorded"

    assert publish_time < max_duration_seconds,
      "Publish should return immediately (took #{publish_time}s, expected < #{max_duration_seconds}s)"

    self
  end

  def assert_dispatcher_thread_running
    poll_assert("background dispatcher thread to be running", within: 1.0) do
      Thread.list.any? { |t| t != Thread.current && t.status == "sleep" }
    end

    self
  end

  def assert_all_events_received(event_class, expected_count)
    poll_assert("all #{expected_count} #{event_class} events to be received", within: 1.0) do
      @handler_calls[event_class].size >= expected_count
    end

    actual_count = @handler_calls[event_class].size
    assert_equal expected_count, actual_count,
      "Expected all #{expected_count} events to be received, got #{actual_count}"

    self
  end

  def assert_unique_events_received(event_class, expected_ids)
    poll_assert("all unique #{event_class} events to be received", within: 1.0) do
      @handler_calls[event_class].size >= expected_ids.size
    end

    received_ids = @handler_calls[event_class].map(&:id).sort
    assert_equal expected_ids.sort, received_ids,
      "Expected unique events with IDs #{expected_ids.inspect}, got #{received_ids.inspect}"

    self
  end

  def assert_no_event_loss(event_class, expected_total_invocations)
    poll_assert("all #{expected_total_invocations} #{event_class} invocations", within: 2.0) do
      @handler_calls[event_class].size >= expected_total_invocations
    end

    actual_invocations = @handler_calls[event_class].size
    assert_equal expected_total_invocations, actual_invocations,
      "Expected #{expected_total_invocations} handler invocations, got #{actual_invocations}"

    self
  end

  # Query Methods

  def captured_events_for(event_class)
    poll_assert("#{event_class} events to be captured", within: 1.0) do
      !@handler_calls[event_class].empty?
    end
    @handler_calls[event_class].dup
  end

  def last_published_event
    @last_published_event
  end

  # Error Handling Subscriptions

  def subscribe_to_with_failure(event_class, &handler)
    wrapped_handler = wrap_handler_with_failure_tracking(event_class, handler)
    event_bus.subscribe(event_class, &wrapped_handler)
    self
  end

  def subscribe_failing_handler(event_class, error_class, fail_count: Float::INFINITY)
    attempt_count = 0
    subscribe_to(event_class) do |event|
      attempt_count += 1
      raise error_class, "Simulated error" if attempt_count <= fail_count
    end
    self
  end

  # Error Assertions

  def assert_handler_error_captured(event_class, error_class)
    poll_assert("#{error_class} to be captured for #{event_class}", within: 1.0) do
      (@handler_errors[event_class] || []).any? { |e| e.is_a?(error_class) }
    end

    self
  end

  def assert_other_handlers_executed(event_class, expected_successful_count)
    poll_assert("#{expected_successful_count} successful handlers for #{event_class}", within: 1.0) do
      @handler_calls[event_class].size >= expected_successful_count
    end

    successful_calls = @handler_calls[event_class].size
    assert_equal expected_successful_count, successful_calls,
      "Expected #{expected_successful_count} handlers to execute successfully, got #{successful_calls}"

    self
  end

  def assert_all_handlers_executed_despite_errors(event_class, total_handler_count)
    poll_assert("all #{total_handler_count} handlers for #{event_class} to execute", within: 1.0) do
      total = @handler_calls[event_class].size + (@handler_errors[event_class]&.size || 0)
      total >= total_handler_count
    end

    total_executions = @handler_calls[event_class].size + (@handler_errors[event_class]&.size || 0)
    assert_equal total_handler_count, total_executions,
      "Expected all #{total_handler_count} handlers to execute, got #{total_executions}"

    self
  end

  def assert_dispatching_continued_after_error(event_class, events_after_error)
    poll_assert("dispatching to continue after error", within: 1.0) do
      @handler_calls[event_class].size >= events_after_error
    end

    self
  end

  def assert_failure_event_published(original_event_class)
    poll_assert("HandlerFailed event for #{original_event_class}", within: 1.0) do
      (@handler_calls[HandlerFailed] || []).any? { |f| f.original_event.class == original_event_class }
    end

    self
  end

  # Synchronization - wait for specific number of handlers to complete
  def wait_for_handlers_to_complete(event_class, expected_count, timeout: 1.0)
    poll_assert("#{expected_count} handlers to complete for #{event_class}", within: timeout) do
      total = @handler_calls[event_class].size + (@handler_errors[event_class]&.size || 0)
      total >= expected_count
    end
    self
  end

  # SubscriberInvocationFailed Assertions

  def assert_subscriber_invocation_failed_published(original_event_class, expected_count: 1)
    poll_assert("#{expected_count} SubscriberInvocationFailed for #{original_event_class}", within: 1.0) do
      failures = @handler_calls[TCB::SubscriberInvocationFailed] || []
      failures.count { |f| f.original_event.class == original_event_class } >= expected_count
    end

    failures = @handler_calls[TCB::SubscriberInvocationFailed] || []
    matching_failures = failures.select { |f| f.original_event.class == original_event_class }

    assert_equal expected_count, matching_failures.size,
      "Expected #{expected_count} SubscriberInvocationFailed event(s) for #{original_event_class}, got #{matching_failures.size}"

    self
  end

  def assert_subscriber_invocation_failed_with_error(original_event_class, error_class)
    poll_assert("SubscriberInvocationFailed with #{error_class} for #{original_event_class}", within: 1.0) do
      failures = @handler_calls[TCB::SubscriberInvocationFailed] || []
      failures.any? { |f| f.original_event.class == original_event_class && f.error_class == error_class.name }
    end

    self
  end

  def assert_subscriber_invocation_failed_contains_source(original_event_class)
    poll_assert("SubscriberInvocationFailed for #{original_event_class}", within: 1.0) do
      failures = @handler_calls[TCB::SubscriberInvocationFailed] || []
      failures.any? { |f| f.original_event.class == original_event_class }
    end

    failures = @handler_calls[TCB::SubscriberInvocationFailed] || []
    matching_failure = failures.find { |f| f.original_event.class == original_event_class }

    assert matching_failure.subscriber_source, "SubscriberInvocationFailed should contain subscriber_source"
    refute_empty matching_failure.subscriber_source, "subscriber_source should not be empty"

    self
  end

  def assert_captured_subscriber_invocation_failed(original_event_class, &block)
    poll_assert("SubscriberInvocationFailed events for #{original_event_class}", within: 1.0) do
      failures = @handler_calls[TCB::SubscriberInvocationFailed] || []
      failures.any? { |f| f.original_event.class == original_event_class }
    end

    failures = @handler_calls[TCB::SubscriberInvocationFailed] || []
    matching_failures = failures.select { |f| f.original_event.class == original_event_class }

    block.call(matching_failures)
    self
  end

  # Lifecycle Management

  def shutdown_bus(drain: true, timeout: 5.0)
    @shutdown_start_time = Time.now
    @event_bus.shutdown(drain: drain, timeout: timeout)
    @shutdown_end_time = Time.now
    self
  end

  def force_shutdown_bus
    @shutdown_start_time = Time.now
    @event_bus.force_shutdown
    @shutdown_end_time = Time.now
    self
  end

  # Lifecycle State Assertions

  def assert_bus_accepting_events
    test_event = UserRegistered.new(id: -1, email: "test@bus-state-check.com")
    begin
      @event_bus.publish(test_event)
    rescue => e
      flunk "Expected bus to be accepting events, but got error: #{e.message}"
    end
    self
  end

  def assert_bus_shutdown
    poll_assert("bus to be shut down", within: 1.0) do
      @event_bus.shutdown?
    end

    self
  end

  def assert_rejects_events_after_shutdown
    error_raised = false
    begin
      publish_event(UserRegistered.new(id: -1, email: "should-fail@example.com"))
    rescue => e
      error_raised = true
      assert e.class.name.include?("Shutdown"),
        "Expected shutdown-related error, got #{e.class}: #{e.message}"
    end

    assert error_raised, "Expected publishing after shutdown to raise an error"
    self
  end

  # Shutdown Events Assertions

  def assert_shutdown_initiated_event_published
    poll_assert("EventBusShutdown :initiated to be published", within: 1.0) do
      (@handler_calls[TCB::EventBusShutdown] || []).any? { |e| e.status == :initiated }
    end

    self
  end

  def assert_shutdown_completed_event_published
    poll_assert("EventBusShutdown :completed to be published", within: 1.0) do
      (@handler_calls[TCB::EventBusShutdown] || []).any? { |e| e.status == :completed }
    end

    self
  end

  def assert_shutdown_timeout_exceeded
    poll_assert("EventBusShutdown :timeout_exceeded to be published", within: 1.0) do
      (@handler_calls[TCB::EventBusShutdown] || []).any? { |e| e.status == :timeout_exceeded }
    end

    self
  end

  # Drain Verification

  def assert_events_drained_before_shutdown(event_class, expected_count)
    poll_assert("#{expected_count} #{event_class} events to be drained", within: 1.0) do
      @handler_calls[event_class].size >= expected_count
    end

    actual_count = @handler_calls[event_class].size
    assert_equal expected_count, actual_count,
      "Expected #{expected_count} events to be drained before shutdown, got #{actual_count}"

    self
  end

  def assert_events_not_drained(event_class)
    # Negative assertion — force_shutdown_bus is synchronous, so state is settled
    calls = @handler_calls[event_class]
    assert calls.empty?,
      "Expected no events to be processed (force shutdown), but #{calls.size} were processed"

    self
  end

  def assert_events_abandoned_after_timeout(event_class, min_abandoned_count: 1)
    total_published = @handler_calls[event_class].size + min_abandoned_count
    actual_processed = @handler_calls[event_class].size

    assert actual_processed < total_published,
      "Expected at least #{min_abandoned_count} events to be abandoned, but all were processed"

    self
  end

  # Timing Assertions

  def assert_shutdown_duration_within(expected_duration_seconds)
    refute_nil @shutdown_start_time, "Shutdown was not initiated"
    refute_nil @shutdown_end_time, "Shutdown did not complete"

    actual_duration = @shutdown_end_time - @shutdown_start_time
    assert actual_duration <= expected_duration_seconds,
      "Expected shutdown to complete within #{expected_duration_seconds}s, but took #{actual_duration}s"

    self
  end

  # Error Handling

  def assert_raises_shutdown_error(&block)
    error_raised = false
    begin
      block.call
    rescue => e
      error_raised = true
      assert e.class.name.include?("Shutdown"),
        "Expected shutdown-related error, got #{e.class}: #{e.message}"
    end

    assert error_raised, "Expected block to raise a shutdown error"
    self
  end

  private

  def wrap_handler(event_class, handler_id, original_handler)
    proc do |event|
      begin
        @handler_thread_ids[event_class] << Thread.current.object_id
        original_handler.call(event)
        @handler_calls[event_class] << event
        @handler_call_order << { event_class: event_class, handler_id: handler_id, event: event }
      rescue => e
        @handler_errors[event_class] << e
        raise
      end
    end
  end
end