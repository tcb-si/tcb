module EventBusDSL
  attr_reader :event_bus

  # Setup & Initialization

  def create_event_bus(options = {})
    @event_bus = TCB::EventBus.new
    @handler_calls = Hash.new { |h, k| h[k] = [] }
    @named_handlers = {}
    @handler_call_order = []
    self
  end

  def create_synchronous_bus
    # For now, same as regular bus - we'll add sync mode later
    create_event_bus(sync_mode: true)
  end

  # Event Publication

  def publish_event(event)
    @last_published_event = event_bus.publish(event)
    self
  end

  def publish_events(*events)
    events.each { |event| publish_event(event) }
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

  def last_published_event
    @last_published_event
  end

  private

  def wrap_handler(event_class, handler_id, original_handler)
    proc do |event|
      # Record the call
      @handler_calls[event_class] << event
      @handler_call_order << { event_class: event_class, handler_id: handler_id, event: event }

      # Execute original handler
      original_handler.call(event)
    end
  end

  def wait_for_dispatch
    # Give dispatcher thread time to process
    # In future, we'll make this smarter with synchronous mode
    sleep 0.1
  end
end
