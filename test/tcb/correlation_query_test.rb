# frozen_string_literal: true

require_relative "../test_helper"
require_relative '../support/active_record_setup_no_models'

module TCB
  class CorrelationQueryTest < Minitest::Test

    module Sales
      OrderPlaced = Data.define(:order_id, :customer)
      PlaceOrder  = Data.define(:order_id, :customer) do
        def validate! = nil
      end
    end

    module Warehouse
      StockReserved = Data.define(:order_id)
    end

    class SalesOrder
      include TCB::RecordsEvents
      def place(order_id:, customer:) = record Sales::OrderPlaced.new(order_id:, customer:)
    end

    class PlaceOrderHandler
      def call(command)
        order = SalesOrder.new
        events = TCB.record(events_from: [order]) do
          order.place(order_id: command.order_id, customer: command.customer)
        end
        TCB.publish(*events)
      end
    end

    module Sales
      include TCB::Domain
      persist events(OrderPlaced, stream_id_from_event: :order_id)
      handle PlaceOrder, with(PlaceOrderHandler)
    end

    module Warehouse
      include TCB::Domain
      persist events(StockReserved, stream_id_from_event: :order_id)
    end

    def setup
      TCB.domain_modules = [Sales, Warehouse]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::InMemory.new
      end
    end

    def teardown
      TCB.reset!
    end

    def test_read_correlation_returns_envelopes_for_correlation_id
      correlation_id = TCB.dispatch(Sales::PlaceOrder.new(order_id: 1, customer: "Alice"))
      results = TCB.read_correlation(correlation_id).to_a

      assert_equal 1, results.size
      assert results.all? { |e| e.correlation_id == correlation_id }
    end

  end
end
