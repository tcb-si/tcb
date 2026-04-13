# frozen_string_literal: true

require_relative '../test_helper'

module TCB
  class EventQueryTest < Minitest::Test

    module Orders
      include TCB::HandlesEvents

      persist events(
        OrderPlaced,
        PaymentProcessed,
        stream_id_from: :order_id
      )
    end

    def setup
      TCB.instance_variable_set(:@config, nil)
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new
        c.event_store = TCB::EventStore::InMemory.new
        c.event_handlers = [Orders]
      end

      @store = TCB.config.event_store
      @stream_id = "tcb/event_query_test/orders|42"

      @store.append(
        stream_id: @stream_id,
        events: [
          OrderPlaced.new(order_id: 42, total: 100.0),
          PaymentProcessed.new(order_id: 42, amount: 100.0)
        ]
      )

      @store.append(
        stream_id: "tcb/event_query_test/orders|99",
        events: [
          OrderPlaced.new(order_id: 99, total: 200.0)
        ]
      )
    end

    def teardown
      TCB.config.event_bus.force_shutdown
      TCB.instance_variable_set(:@config, nil)
    end

    # Test: .stream returns envelopes for that aggregate
    def test_stream_returns_envelopes_for_aggregate
      envelopes = TCB.read(Orders).stream(42).to_a

      assert_equal 2, envelopes.size
      assert_equal @stream_id, envelopes.first.stream_id
      assert_instance_of OrderPlaced, envelopes.first.event
      assert_instance_of PaymentProcessed, envelopes.last.event
    end

    # Test: .stream for unknown aggregate returns []
    def test_stream_returns_empty_for_unknown_aggregate
      envelopes = TCB.read(Orders).stream(999).to_a

      assert_equal [], envelopes
    end

    # Test: .stream isolates by aggregate id
    def test_stream_isolates_by_aggregate_id
      envelopes = TCB.read(Orders).stream(99).to_a

      assert_equal 1, envelopes.size
      assert_equal 99, envelopes.first.event.order_id
    end

    # Test: .after_version filters envelopes
    def test_after_version_filters_envelopes
      envelopes = TCB.read(Orders).stream(42).after_version(1).to_a

      assert_equal 1, envelopes.size
      assert_equal 2, envelopes.first.version
      assert_instance_of PaymentProcessed, envelopes.first.event
    end

    # Test: .occurred_after filters envelopes
    def test_occurred_after_filters_envelopes
      t1 = Time.now - 10
      t2 = Time.now + 10

      @store.append(stream_id: "tcb/event_query_test/orders|77", events: [OrderPlaced.new(order_id: 77, total: 50.0)], occurred_at: t1)
      @store.append(stream_id: "tcb/event_query_test/orders|77", events: [PaymentProcessed.new(order_id: 77, amount: 50.0)], occurred_at: t2)

      envelopes = TCB.read(Orders).stream(77).occurred_after(t1 + 1).to_a

      assert_equal 1, envelopes.size
      assert_instance_of PaymentProcessed, envelopes.first.event
    end

    # Test: .after_version and .occurred_after can be chained
    def test_after_version_and_occurred_after_can_be_chained
      t_past = Time.now - 100

      envelopes = TCB.read(Orders).stream(42).after_version(0).occurred_after(t_past).to_a

      assert_equal 2, envelopes.size
    end

    # Test: query is lazy - no execution without .to_a
    def test_query_is_lazy
      query = TCB.read(Orders).stream(42)

      assert_instance_of TCB::EventQuery, query
    end

    # Test: filters return new query instances (immutable)
    def test_filters_return_new_query_instances
      base     = TCB.read(Orders).stream(42)
      filtered = base.after_version(1)

      refute_same base, filtered
    end
  end
end
