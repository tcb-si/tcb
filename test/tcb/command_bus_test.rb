require_relative '../test_helper'

module TCB
  class CommandBusTest < Minitest::Test
    OrderPlaced = Data.define(:order_id, :customer)

    class Order
      include TCB::RecordsEvents
      def place(order_id:, customer:) = record OrderPlaced.new(order_id:, customer:)
    end

    PlaceOrder = Data.define(:order_id, :customer) do
      def validate!
        raise ArgumentError, "customer missing" if customer.nil?
      end
    end

    CommandWithoutValidate = Data.define(:id)
    UnregisteredCommand    = Data.define(:id) do
      def validate! = nil
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

    module TestOrders
      include TCB::HandlesCommands

      handle PlaceOrder, with(PlaceOrderHandler)
    end

    def setup
      TCB.domain_modules = [TestOrders]
      TCB.configure do |c|
        c.event_bus      = TCB::EventBus.new
      end
    end

    def teardown
      TCB.reset!
    end

    def test_dispatch_calls_validate_before_handler
      assert_raises(ArgumentError) do
        TCB.dispatch(PlaceOrder.new(order_id: 1, customer: nil))
      end
    end

    def test_dispatch_raises_when_validate_not_defined
      assert_raises(NotImplementedError) do
        TCB.dispatch(CommandWithoutValidate.new(id: 1))
      end
    end

    def test_dispatch_calls_registered_handler
      events = TCB.dispatch(PlaceOrder.new(order_id: 1, customer: "Alice"))
      assert_includes events, OrderPlaced.new(order_id: 1, customer: "Alice")
    end

    def test_dispatch_returns_events_from_handler
      events = TCB.dispatch(PlaceOrder.new(order_id: 1, customer: "Alice"))
      assert_equal [OrderPlaced.new(order_id: 1, customer: "Alice")], events
    end

    def test_dispatch_raises_when_no_handler_registered
      assert_raises(TCB::CommandHandlerNotFound) do
        TCB.dispatch(UnregisteredCommand.new(id: 1))
      end
    end
  end
end
