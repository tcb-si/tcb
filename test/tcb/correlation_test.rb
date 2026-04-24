# frozen_string_literal: true

require_relative "../test_helper"
require_relative '../support/active_record_setup_no_models'

module TCB
  class CorrelationTest < Minitest::Test
    include TCB::MinitestHelpers

    # --- Events ---
    module Sales
      OrderPlaced = Data.define(:order_id, :customer)
      PlaceOrder  = Data.define(:order_id, :customer) do
        def validate! = nil
      end
    end

    module Warehouse
      StockReserved = Data.define(:order_id)
    end

    module Notifications
      CustomerNotified = Data.define(:order_id)
    end

    # --- Aggregates ---
    class SalesOrder
      include TCB::RecordsEvents
      def place(order_id:, customer:) = record Sales::OrderPlaced.new(order_id:, customer:)
    end

    class WarehouseStock
      include TCB::RecordsEvents
      def reserve(order_id:) = record Warehouse::StockReserved.new(order_id:)
    end

    # --- Handlers ---
    class PlaceOrderHandler
      def call(command)
        order = SalesOrder.new
        events = TCB.record(events_from: [order]) do
          order.place(order_id: command.order_id, customer: command.customer)
        end
        TCB.publish(*events)
      end
    end

    class ReserveStock
      def call(event)
        stock = WarehouseStock.new
        events = TCB.record(events_from: [stock]) do
          stock.reserve(order_id: event.order_id)
        end
        TCB.publish(*events)
      end
    end

    class NotifyCustomer
      def call(event)
        events = TCB.record(events: [Notifications::CustomerNotified.new(order_id: event.order_id)])
        TCB.publish(*events)
      end
    end

    # --- Domain modules ---
    module Sales
      include TCB::Domain

      persist events(OrderPlaced, stream_id_from_event: :order_id)
      handle PlaceOrder, with(PlaceOrderHandler)
      on OrderPlaced, react_with(ReserveStock)
    end

    module Warehouse
      include TCB::Domain

      persist events(StockReserved, stream_id_from_event: :order_id)
      on StockReserved, react_with(NotifyCustomer)
    end

    module Notifications
      include TCB::HandlesEvents
    end

    # --- Setup ---
    def setup
      @customer_notified_envelope = nil

      TCB.domain_modules = [Sales, Warehouse, Notifications]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::InMemory.new
      end

      TCB.config.event_bus.subscribe(Notifications::CustomerNotified) do |envelope|
        @customer_notified_envelope = envelope
      end
    end

    def teardown
      TCB.reset!
    end

    # --- Tests ---

    def test_dispatch_returns_correlation_id
      correlation_id = TCB.dispatch(Sales::PlaceOrder.new(order_id: 1, customer: "Alice"))
      assert_kind_of String, correlation_id
      refute_nil correlation_id
    end

    def test_correlation_id_can_be_provided_externally
      correlation_id = TCB.dispatch(Sales::PlaceOrder.new(order_id: 2, customer: "Bob"), correlation_id: "req-abc")
      assert_equal "req-abc", correlation_id
    end

    def test_order_placed_has_correlation_id_and_no_causation
      correlation_id = TCB.dispatch(Sales::PlaceOrder.new(order_id: 3, customer: "Carol"))
      order_placed = TCB.read(Sales).stream(3).to_a.find { |e| e.event.is_a?(Sales::OrderPlaced) }

      assert_equal correlation_id, order_placed.correlation_id
      assert_nil order_placed.causation_id
    end

    def test_stock_reserved_inherits_correlation_and_causation
      correlation_id = TCB.dispatch(Sales::PlaceOrder.new(order_id: 4, customer: "Dave"))
      order_placed   = TCB.read(Sales).stream(4).to_a.find { |e| e.event.is_a?(Sales::OrderPlaced) }
      stock_reserved = TCB.read(Warehouse).stream(4).to_a.find { |e| e.event.is_a?(Warehouse::StockReserved) }

      assert_equal correlation_id,        stock_reserved.correlation_id
      assert_equal order_placed.event_id, stock_reserved.causation_id
    end

    def test_customer_notified_inherits_correlation_and_causation
      correlation_id = TCB.dispatch(Sales::PlaceOrder.new(order_id: 5, customer: "Eve"))
      stock_reserved = TCB.read(Warehouse).stream(5).to_a.find { |e| e.event.is_a?(Warehouse::StockReserved) }

      assert_equal correlation_id,          @customer_notified_envelope.correlation_id
      assert_equal stock_reserved.event_id, @customer_notified_envelope.causation_id
    end

    def test_record_outside_dispatch_has_nil_correlation_and_causation
      envelopes = TCB.record(events: [Sales::OrderPlaced.new(order_id: 99, customer: "Zara")])

      assert_nil envelopes.first.correlation_id
      assert_nil envelopes.first.causation_id
    end
  end
end
