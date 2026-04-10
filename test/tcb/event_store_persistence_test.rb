require_relative '../test_helper'

module TCB
  class EventStorePersistenceTest < Minitest::Test
    include PollAssert

    OrderCancelled = Data.define(:order_id)

    module TestOrders
      include TCB::HandlesEvents

      persist events(
        OrderPlaced,
        OrderCancelled,
        stream_id_from: :order_id
      )
    end

    module TestPayments
      include TCB::HandlesEvents

      persist events(
        PaymentProcessed,
        stream_id_from: :order_id
      )
    end

    class TestOrder
      include TCB::RecordsEvents
      attr_reader :id

      def initialize(id:) = @id = id
      def place(total:) = record OrderPlaced.new(order_id: id, total: total)
      def cancel = record OrderCancelled.new(order_id: id)
    end

    def setup
      TCB.instance_variable_set(:@config, nil)
      TCB.configure do |c|
        c.event_bus      = TCB::EventBus.new
        c.event_store    = TCB::EventStore::InMemory.new
        c.event_handlers = [TestOrders, TestPayments]
      end
    end

    def teardown
      TCB.config.event_bus.force_shutdown
      TCB.instance_variable_set(:@config, nil)
    end

    # Osnovni persistence
    def test_record_persists_marked_events
      order = TestOrder.new(id: 42)
      TCB.record(aggregates: [order]) { order.place(total: 100.0) }

      envelopes = TCB.config.event_store.read("tcb/event_store_persistence_test/test_orders|42")
      assert_equal 1, envelopes.size
      assert_instance_of OrderPlaced, envelopes.first.event
    end

    def test_record_persists_multiple_events_in_same_registration
      order = TestOrder.new(id: 42)
      TCB.record(aggregates: [order]) do
        order.place(total: 100.0)
        order.cancel
      end

      envelopes = TCB.config.event_store.read("tcb/event_store_persistence_test/test_orders|42")
      assert_equal 2, envelopes.size
      assert_equal [1, 2], envelopes.map(&:version)
    end

    def test_record_persists_events_from_different_domains
      order = TestOrder.new(id: 42)
      TCB.record(aggregates: [order]) do
        order.place(total: 100.0)
        order.record PaymentProcessed.new(order_id: 42, amount: 100.0)
      end

      order_envelopes   = TCB.config.event_store.read("tcb/event_store_persistence_test/test_orders|42")
      payment_envelopes = TCB.config.event_store.read("tcb/event_store_persistence_test/test_payments|42")
      assert_equal 1, order_envelopes.size
      assert_equal 1, payment_envelopes.size
    end

    def test_record_does_not_persist_unmarked_events
      order = TestOrder.new(id: 42)
      TCB.record(aggregates: [order]) { order.place(total: 100.0) }

      envelopes = TCB.config.event_store.read("tcb/event_store_persistence_test/test_orders|99")
      assert_equal [], envelopes
    end

    def test_record_persists_events_from_multiple_aggregates
      order1 = TestOrder.new(id: 1)
      order2 = TestOrder.new(id: 2)

      TCB.record(aggregates: [order1, order2]) do
        order1.place(total: 100.0)
        order2.place(total: 200.0)
      end

      assert_equal 1, TCB.config.event_store.read("tcb/event_store_persistence_test/test_orders|1").size
      assert_equal 1, TCB.config.event_store.read("tcb/event_store_persistence_test/test_orders|2").size
    end

    # Persistence pred publishanjem
    def test_events_are_persisted_before_publishing
      persisted_before_publish = false

      TCB.config.event_bus.subscribe(OrderPlaced) do |event|
        envelopes = TCB.config.event_store.read("tcb/event_store_persistence_test/test_orders|42")
        persisted_before_publish = envelopes.any?
      end

      order = TestOrder.new(id: 42)
      events = TCB.record(aggregates: [order]) { order.place(total: 100.0) }
      TCB.publish(*events)

      poll_assert("handler called") { persisted_before_publish }
      assert persisted_before_publish
    end

    # Exception → ni persistence
    def test_exception_in_record_does_not_persist_events
      order = TestOrder.new(id: 42)

      assert_raises(RuntimeError) do
        TCB.record(aggregates: [order]) do
          order.place(total: 100.0)
          raise "something went wrong"
        end
      end

      assert_equal [], TCB.config.event_store.read("tcb/event_store_persistence_test/test_orders|42")
    end
  end
end
