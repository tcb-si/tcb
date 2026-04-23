require_relative '../test_helper'

module TCB
  class DomainTest < Minitest::Test
    include TCB::MinitestHelpers

    CALLED = []

    OrderPlaced = Data.define(:order_id, :customer)

    PlaceOrder = Data.define(:order_id, :customer) do
      def validate! = nil
    end

    class Order
      include TCB::RecordsEvents
      def place(order_id:, customer:) = record OrderPlaced.new(order_id:, customer:)
    end

    class PlaceOrderHandler
      def call(command)
        order = Order.new
        events = TCB.record(events_from: [order]) do
          order.place(order_id: command.order_id, customer: command.customer)
        end
        TCB.publish(*events)
      end
    end

    class SendConfirmation
      def call(event) = CALLED << :send_confirmation
    end

    class UpdateInventory
      def call(event) = CALLED << :update_inventory
    end

    module Orders
      include TCB::Domain

      handle PlaceOrder, with(PlaceOrderHandler)
      on OrderPlaced, react_with(SendConfirmation, UpdateInventory)
    end

    def setup
      CALLED.clear

      TCB.domain_modules = [Orders]
      TCB.configure do |c|
        c.event_bus = TCB::EventBus.new
      end
    end

    def teardown
      TCB.reset!
    end

    def test_dispatch_triggers_event_handler_via_domain_module
      TCB.dispatch(PlaceOrder.new(order_id: 1, customer: "Alice"))
      poll_assert("send confirmation called") { CALLED.include?(:send_confirmation) }
    end

    def test_domain_module_handles_both_commands_and_events
      TCB.dispatch(PlaceOrder.new(order_id: 1, customer: "Alice"))
      poll_assert("all handlers called") { CALLED.size == 2 }
      assert_includes CALLED, :send_confirmation
      assert_includes CALLED, :update_inventory
    end
  end
end
