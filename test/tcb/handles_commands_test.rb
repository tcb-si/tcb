require_relative '../test_helper'

module TCB
  class HandlesCommandsTest < Minitest::Test
    module TestOrders
      include TCB::HandlesCommands

      PlaceOrder  = Data.define(:customer, :items)
      CancelOrder = Data.define(:order_id, :reason)

      PlaceOrderHandler = Class.new do
        define_method(:call) { |cmd| }
      end

      CancelOrderHandler = Class.new do
        define_method(:call) { |cmd| }
      end

      handle PlaceOrder,  with(PlaceOrderHandler)
      handle CancelOrder, with(CancelOrderHandler)
    end

    def test_registers_single_handler_for_command
      registrations = TestOrders.command_handler_registrations
      assert_equal 2, registrations.size

      reg = registrations.first
      assert_equal TestOrders::PlaceOrder,        reg.command_class
      assert_equal TestOrders::PlaceOrderHandler, reg.handler
    end

    def test_with_raises_argument_error_with_no_handler
      assert_raises(ArgumentError) do
        Module.new do
          include TCB::HandlesCommands
          with()
        end
      end
    end

    def test_with_raises_argument_error_with_multiple_handlers
      assert_raises(ArgumentError) do
        Module.new do
          include TCB::HandlesCommands
          with(Class.new, Class.new)
        end
      end
    end

    def test_name_error_raised_when_constant_missing
      assert_raises(NameError) do
        Module.new do
          include TCB::HandlesCommands
          handle TestOrders::PlaceOrder, with(NonExistentHandler)
        end
      end
    end
  end
end
