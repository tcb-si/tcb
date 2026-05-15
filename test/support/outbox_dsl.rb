# frozen_string_literal: true

module OutboxDSL
  def assert_outbox_pending(handler:, count: 1)
    matching = @outbox_store.pending.select { |e| e.handler_class == handler.name }
    assert_equal count, matching.size,
      "Expected #{count} pending outbox entry/entries for #{handler}, got #{matching.size}"
    self
  end

  def assert_outbox_delivered(handler:)
    matching = @outbox_store.all.select { |e| e.handler_class == handler.name && e.status == :delivered }
    assert_predicate matching, :any?,
      "Expected at least one delivered outbox entry for #{handler}, but none found"
    self
  end

  def assert_outbox_failed(handler:)
    matching = @outbox_store.all.select { |e| e.handler_class == handler.name && e.status == :failed }
    assert_predicate matching, :any?,
      "Expected at least one failed outbox entry for #{handler}, but none found"
    self
  end

  def simulate_stale_lock(handler:, age:)
    entry = @outbox_store.pending.find { |e| e.handler_class == handler.name }
    raise "No pending entry found for #{handler}" unless entry

    locked = @outbox_store.lock(entry)
    stale  = locked.with(locked_at: Time.now - age)
    @outbox_store.lock(stale, locked_at: stale.locked_at)
    self
  end

  def with_failing_handler(handler_class, raises:)
    original = handler_class.instance_method(:call)
    handler_class.define_method(:call) { |_| raise raises, raises.to_s }
    yield
  ensure
    handler_class.define_method(:call, original)
  end
end
