require_relative '../test_helper'

module TCB
  class HandlesEventsTest < Minitest::Test
    include TCB::MinitestHelpers
    # Primitive test double for verifying that handlers are called when events are published.
    CALLED = []

    module TestOrders
      include TCB::HandlesEvents

      OrderPlaced   = Data.define(:order_id)
      OrderCancelled = Data.define(:order_id, :reason)
      FailureAnticipated = Data.define(:order_id)

      ReserveInventory = Class.new do
        define_method(:call) { |event| CALLED << :reserve_inventory }
      end

      ChargePayment = Class.new do
        define_method(:call) { |event| CALLED << :charge_payment }
      end

      RefundPayment = Class.new do
        define_method(:call) { |event| CALLED << :refund_payment }
      end

      FailGracefully = Class.new do
        define_method(:call) { |event| raise StandardError, "boom" }
      end

      on OrderPlaced, react_with(
        ReserveInventory,
        ChargePayment
      )

      on OrderCancelled, react_with(RefundPayment)

      on FailureAnticipated, react_with(
        FailGracefully,
        ReserveInventory
      )
    end

    def setup
      CALLED.clear
      TCB.instance_variable_set(:@config, nil)
      TCB.configure do |c|
        c.event_bus = TCB::EventBus.new
        c.domain_modules = [TestOrders]
      end
    end

    def teardown
      TCB.config.event_bus.force_shutdown
      TCB.instance_variable_set(:@config, nil)
    end

    def test_handler_called_when_event_published
      TCB.publish(TestOrders::OrderPlaced.new(order_id: 1))
      poll_assert("reserve inventory was called") { CALLED.include?(:reserve_inventory) }
    end

    def test_multiple_handlers_called_for_same_event
      TCB.publish(TestOrders::OrderPlaced.new(order_id: 1))
      poll_assert("all handlers called") { CALLED.size == 2 }
      assert_equal [:reserve_inventory, :charge_payment], CALLED
    end

    def test_correct_handlers_called_for_each_event_type
      TCB.publish(TestOrders::OrderCancelled.new(order_id: 1, reason: "changed mind"))
      poll_assert("refund payment was called") { CALLED.include?(:refund_payment) }
      refute_includes CALLED, :reserve_inventory
      refute_includes CALLED, :charge_payment
    end

    def test_name_error_raised_when_constant_missing
      assert_raises(NameError) do
        Module.new do
          include TCB::HandlesEvents
          on TestOrders::OrderPlaced, react_with(NonExistentHandler)
        end
      end
    end

    def test_failing_handler_does_not_prevent_other_handlers
      # subscribe na SubscriberInvocationFailed za observability
      failures = []
      TCB.config.event_bus.subscribe(TCB::SubscriberInvocationFailed) { |e| failures << e }

      TCB.publish(TestOrders::FailureAnticipated.new(order_id: 1))

      poll_assert("reserve inventory called despite failure") { CALLED.include?(:reserve_inventory) }
      poll_assert("failure event published") { failures.any? }

      assert_equal 1, failures.size
      assert_equal "StandardError", failures.first.error_class
      assert_equal TestOrders::FailureAnticipated, failures.first.original_event.class
    end
  end
end
