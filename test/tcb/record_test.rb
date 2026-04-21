require_relative '../test_helper'

module TCB
  class RecordTest < Minitest::Test
    OrderPlaced       = Data.define(:order_id, :customer)
    InventoryReserved = Data.define(:item_id)

    class Order
      include TCB::RecordsEvents
      def place(order_id:, customer:) = record OrderPlaced.new(order_id:, customer:)
    end

    class Inventory
      include TCB::RecordsEvents
      def reserve(item_id:) = record InventoryReserved.new(item_id:)
    end

    def test_record_returns_events_from_single_aggregate
      order = Order.new
      events = TCB.record(events_from: [order]) do
        order.place(order_id: 1, customer: "Alice")
      end
      assert_equal [OrderPlaced.new(order_id: 1, customer: "Alice")], events
    end

    def test_record_returns_events_from_multiple_events_from
      order     = Order.new
      inventory = Inventory.new
      events = TCB.record(events_from: [order, inventory]) do
        order.place(order_id: 1, customer: "Alice")
        inventory.reserve(item_id: 42)
      end
      assert_includes events, OrderPlaced.new(order_id: 1, customer: "Alice")
      assert_includes events, InventoryReserved.new(item_id: 42)
    end

    def test_record_returns_empty_when_no_events_recorded
      order = Order.new
      events = TCB.record(events_from: [order]) { }
      assert_equal [], events
    end

    def test_record_propagates_exception_and_discards_events
      order = Order.new
      assert_raises(RuntimeError) do
        TCB.record(events_from: [order]) do
          order.place(order_id: 1, customer: "Alice")
          raise "Something went wrong"
        end
      end
      assert_equal [], order.recorded_events
    end

    def test_record_executes_block_within_transaction
      call_log = []
      fake_transaction = Module.new do
        define_singleton_method(:transaction) do |&block|
          call_log << :transaction_called
          block.call
        end
      end

      order = Order.new
      TCB.record(events_from: [order], within: fake_transaction) do
        order.place(order_id: 1, customer: "Alice")
      end

      assert_includes call_log, :transaction_called
    end

    def test_record_without_transaction_works_normally
      order = Order.new
      events = TCB.record(events_from: [order]) do
        order.place(order_id: 1, customer: "Alice")
      end
      assert_equal [OrderPlaced.new(order_id: 1, customer: "Alice")], events
    end

    def test_record_rolls_back_transaction_on_exception
      rolled_back = false
      fake_transaction = Module.new do
        define_singleton_method(:transaction) do |&block|
          block.call
        rescue
          rolled_back = true
          raise
        end
      end

      order = Order.new
      assert_raises(RuntimeError) do
        TCB.record(events_from: [order], within: fake_transaction) do
          order.place(order_id: 1, customer: "Alice")
          raise "DB error"
        end
      end

      assert rolled_back
      assert_equal [], order.recorded_events
    end

    def test_consecutive_records_are_independent
      order = Order.new
      TCB.record(events_from: [order]) { order.place(order_id: 1, customer: "Alice") }

      events = TCB.record(events_from: [order]) { }
      assert_equal [], events
    end

    def test_record_accepts_direct_events
      events = TCB.record(events: [OrderPlaced.new(order_id: 1, customer: "Alice")])
      assert_equal [OrderPlaced.new(order_id: 1, customer: "Alice")], events
    end

    def test_record_combines_events_from_and_direct_events
      order = Order.new
      events = TCB.record(events_from: [order], events: [InventoryReserved.new(item_id: 42)]) do
        order.place(order_id: 1, customer: "Alice")
      end
      assert_includes events, OrderPlaced.new(order_id: 1, customer: "Alice")
      assert_includes events, InventoryReserved.new(item_id: 42)
      assert_equal 2, events.size
    end

    def test_record_raises_when_neither_events_from_nor_events_given
      assert_raises(ArgumentError) { TCB.record { } }
    end

    def test_record_direct_events_without_block
      events = TCB.record(events: [OrderPlaced.new(order_id: 1, customer: "Alice")])
      assert_equal 1, events.size
    end

    def test_record_without_transaction_adapter_works_normally
      order = Order.new
      events = TCB.record(events_from: [order], within: Object.new) do
        order.place(order_id: 1, customer: "Alice")
      end
      assert_equal [OrderPlaced.new(order_id: 1, customer: "Alice")], events
    end
  end
end
