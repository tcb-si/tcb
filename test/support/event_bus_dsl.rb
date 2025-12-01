module EventBusDSL
  attr_reader :event_bus

  # Setup & Initialization

  def create_event_bus(options = {})
    @event_bus = TCB::EventBus.new
    @handler_calls = Hash.new { |h, k| h[k] = [] }
    @named_handlers = {}
    @handler_call_order = []
    @handler_thread_ids = Hash.new { |h, k| h[k] = [] }
    @main_thread_id = Thread.current.object_id
    @publish_start_time = nil
    @last_publish_duration = nil
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
    wait_for_dispatch

    calls = @handler_calls[event_class]
    assert !calls.empty?, "Expected #{event_class} to be delivered but no calls recorded"

    unless expected_data.empty?
      matching_call = calls.find do |call|
        expected_data.all? { |key, value| call.public_send(key) == value }
      end
      assert matching_call, "Expected #{event_class} with data #{expected_data.inspect} but got #{calls.inspect}"
    end

    self
  end

  def assert_handler_called_times(event_class, expected_count)
    wait_for_dispatch

    actual_count = @handler_calls[event_class].size
    assert_equal expected_count, actual_count,
      "Expected #{event_class} handler to be called #{expected_count} times, but was called #{actual_count} times"

    self
  end

  def assert_handlers_called_in_order(event_class, *handler_ids)
    wait_for_dispatch

    actual_order = @handler_call_order
      .select { |call| call[:event_class] == event_class && call[:handler_id] }
      .map { |call| call[:handler_id] }

    assert_equal handler_ids, actual_order,
      "Expected handlers to be called in order #{handler_ids.inspect}, but got #{actual_order.inspect}"

    self
  end

  def assert_event_not_delivered(event_class)
    wait_for_dispatch

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
    wait_for_dispatch
    events = @handler_calls[event_class]
    block.call(events)
    self
  end

  def assert_handler_executed_asynchronously(event_class)
    wait_for_dispatch

    calls = @handler_calls[event_class]
    assert !calls.empty?, "Expected #{event_class} handler to be called"

    # Verify handler was executed in a different thread
    handler_thread_id = @handler_thread_ids[event_class]&.first
    refute_nil handler_thread_id, "Handler thread ID should be recorded"
    refute_equal @main_thread_id, handler_thread_id,
      "Handler should execute in background thread, not main thread"

    self
  end

  def assert_events_dispatched_concurrently(event_class, expected_count, max_duration_seconds)
    start_time = @publish_start_time
    wait_for_dispatch

    actual_count = @handler_calls[event_class].size
    assert_equal expected_count, actual_count,
      "Expected #{expected_count} events, got #{actual_count}"

    total_time = Time.now - start_time
    assert total_time < max_duration_seconds,
      "Events should be dispatched concurrently (took #{total_time}s, expected < #{max_duration_seconds}s)"

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
    sleep 0.1 # Give dispatcher time to start

    dispatcher_threads = Thread.list.select do |t|
      t != Thread.current && t.status == "sleep"
    end

    assert dispatcher_threads.any?,
      "Background dispatcher thread should be running"

    self
  end

  def assert_all_events_received(event_class, expected_count)
    wait_for_dispatch

    actual_count = @handler_calls[event_class].size
    assert_equal expected_count, actual_count,
      "Expected all #{expected_count} events to be received, got #{actual_count}"

    self
  end

  def assert_unique_events_received(event_class, expected_ids)
    wait_for_dispatch

    received_ids = @handler_calls[event_class].map(&:id).sort
    assert_equal expected_ids.sort, received_ids,
      "Expected unique events with IDs #{expected_ids.inspect}, got #{received_ids.inspect}"

    self
  end

  def assert_no_event_loss(event_class, expected_total_invocations)
    wait_for_dispatch(timeout: 1.0)

    actual_invocations = @handler_calls[event_class].size
    assert_equal expected_total_invocations, actual_invocations,
      "Expected #{expected_total_invocations} handler invocations, got #{actual_invocations}"

    self
  end

  # Query Methods

  def captured_events_for(event_class)
    wait_for_dispatch
    @handler_calls[event_class].dup
  end

  def last_published_event
    @last_published_event
  end

  private

  def wrap_handler(event_class, handler_id, original_handler)
    proc do |event|
      # Record the call and thread ID
      @handler_calls[event_class] << event
      @handler_thread_ids[event_class] << Thread.current.object_id
      @handler_call_order << { event_class: event_class, handler_id: handler_id, event: event }

      # Execute original handler
      original_handler.call(event)
    end
  end

  def wait_for_dispatch(timeout: 0.1)
    # Give dispatcher thread time to process
    # In future, we'll make this smarter with synchronous mode
    sleep timeout
  end
end