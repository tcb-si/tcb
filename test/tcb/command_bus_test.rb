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

    RaiseOnCommandWithoutValidate = Data.define(:id)

    RaiseOnCommandWithoutHandler = Data.define(:id) do
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

    module Orders
      PlaceOrder = Data.define(:order_id, :customer) do
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
    end

    module CommandWithHandlerInDifferentNamespace
      PlaceOrder = Data.define(:order_id, :customer) do
        def validate! = nil
      end
      # Handler namerno ni tukaj
    end

    def setup
      TCB.configure { |c| c.event_bus = TCB::EventBus.new }
    end

    def teardown
      TCB.config.event_bus.force_shutdown
      TCB.instance_variable_set(:@config, nil)
    end

    def test_execute_calls_validate_before_handler
      assert_raises(ArgumentError) do
        TCB.execute(PlaceOrder.new(order_id: 1, customer: nil))
      end
    end

    def test_execute_dispatches_to_correct_handler
      events = TCB.execute(PlaceOrder.new(order_id: 1, customer: "Alice"))
      assert_includes events, OrderPlaced.new(order_id: 1, customer: "Alice")
    end

    def test_execute_raises_when_handler_not_found
      assert_raises(TCB::CommandHandlerNotFound) do
        TCB.execute(RaiseOnCommandWithoutHandler.new(id: 1))
      end
    end

    def test_execute_raises_when_validate_not_defined
      assert_raises(NotImplementedError) do
        TCB.execute(RaiseOnCommandWithoutValidate.new(id: 1))
      end
    end

    def test_execute_returns_events_from_handler
      events = TCB.execute(PlaceOrder.new(order_id: 1, customer: "Alice"))
      assert_equal [OrderPlaced.new(order_id: 1, customer: "Alice")], events
    end

    def test_handler_not_found_error_message_is_helpful
      error = assert_raises(TCB::CommandHandlerNotFound) do
        TCB.execute(RaiseOnCommandWithoutHandler.new(id: 1))
      end
      assert_includes error.message, "RaiseOnCommandWithoutHandler"
      assert_includes error.message, "RaiseOnCommandWithoutHandlerHandler"
    end

    def test_execute_finds_handler_in_same_namespace
      events = TCB.execute(Orders::PlaceOrder.new(order_id: 1, customer: "Alice"))
      assert_includes events, OrderPlaced.new(order_id: 1, customer: "Alice")
    end

    def test_execute_raises_when_handler_not_in_same_namespace
      error = assert_raises(TCB::CommandHandlerNotFound) do
        TCB.execute(CommandWithHandlerInDifferentNamespace::PlaceOrder.new(order_id: 1, customer: "Alice"))
      end
      assert_includes error.message, "PlaceOrderHandler"
    end
  end
end