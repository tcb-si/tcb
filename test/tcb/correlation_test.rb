# frozen_string_literal: true

require_relative "../test_helper"
require_relative '../support/active_record_setup'

module TCB
  class CorrelationTest < Minitest::Test
    include TCB::MinitestHelpers

    OrderPlaced    = Data.define(:order_id)
    StockReserved  = Data.define(:order_id)

    PlaceOrder = Data.define(:order_id) do
      def validate! = nil
    end

    class Order
      include TCB::RecordsEvents
      def place(order_id:) = record OrderPlaced.new(order_id:)
    end

    class PlaceOrderHandler
      def call(command)
        order = Order.new
        events = TCB.record(events_from: [order]) do
          order.place(order_id: command.order_id)
        end
        TCB.publish(*events)
        events
      end
    end

    class ReserveInventory
      def call(event)
        order = Order.new
        events = TCB.record(events_from: [order]) do
          order.record StockReserved.new(order_id: event.order_id)
        end
        TCB.publish(*events)
      end
    end

    module Orders
      include TCB::Domain

      persist events(
        OrderPlaced,
        StockReserved,
        stream_id_from_event: :order_id
      )

      handle PlaceOrder, with(PlaceOrderHandler)
      on OrderPlaced, react_with(ReserveInventory)
    end

    def setup
      @stock_reserved_envelope = nil

      TCB.domain_modules = [Orders]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new
        c.event_store = TCB::EventStore::InMemory.new
      end

      TCB.config.event_bus.subscribe(StockReserved) do |envelope|
        @stock_reserved_envelope = TCB::Envelope.coerce(envelope)
      end
    end

    def teardown
      TCB.reset!
    end

    def test_correlation_id_is_generated_automatically
      envelopes = TCB.dispatch(PlaceOrder.new(order_id: 1))
      refute_nil envelopes.first.correlation_id
    end

    def test_correlation_id_propagates_to_all_envelopes_from_record
      envelopes = TCB.dispatch(PlaceOrder.new(order_id: 1))
      assert_equal 1, envelopes.uniq(&:correlation_id).size
    end

    def test_correlation_id_can_be_overridden
      envelopes = TCB.dispatch(PlaceOrder.new(order_id: 1), correlation_id: "custom-id")
      assert_equal "custom-id", envelopes.first.correlation_id
    end

    def test_causation_id_propagates_through_reactive_handler
      envelopes = TCB.dispatch(PlaceOrder.new(order_id: 1))
      order_placed_envelope = envelopes.first

      poll_assert("stock reserved envelope received") { !@stock_reserved_envelope.nil? }

      assert_equal order_placed_envelope.event_id, @stock_reserved_envelope.causation_id
      assert_equal order_placed_envelope.correlation_id, @stock_reserved_envelope.correlation_id
    end

    def test_persisted_envelope_has_correlation_id
      envelopes = TCB.dispatch(PlaceOrder.new(order_id: 1))
      expected_correlation_id = envelopes.first.correlation_id

      stored = TCB.read(Orders).stream(1).to_a
      assert stored.all? { |e| e.correlation_id == expected_correlation_id }
    end

    def test_persisted_reactive_envelope_has_causation_id
      envelopes = TCB.dispatch(PlaceOrder.new(order_id: 1))
      order_placed_envelope = envelopes.first

      poll_assert("stock reserved stored") do
        TCB.read(Orders).stream(1).to_a.any? { |e| e.event.is_a?(StockReserved) }
      end

      stock_reserved = TCB.read(Orders).stream(1).to_a.find { |e| e.event.is_a?(StockReserved) }
      assert_equal order_placed_envelope.event_id, stock_reserved.causation_id
      assert_equal order_placed_envelope.correlation_id, stock_reserved.correlation_id
    end

    def test_record_without_dispatch_has_nil_correlation_and_causation
      order = Order.new
      envelopes = TCB.record(events_from: [order]) { order.place(order_id: 99) }

      assert_nil envelopes.first.correlation_id
      assert_nil envelopes.first.causation_id
    end
  end
end
