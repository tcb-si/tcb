require_relative '../test_helper'

module TCB
  class EventBusErrorHandlingTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Handler errors are isolated - one failure doesn't affect others
    def test_handler_error_isolation
      subscribe_to(UserRegistered) { |event| } # Success
        .subscribe_to(UserRegistered) { |event| raise StandardError, "Handler failed" } # Fails
        .subscribe_to(UserRegistered) { |event| } # Should still execute
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .wait_for_handlers_to_complete(UserRegistered, 3)
        .assert_other_handlers_executed(UserRegistered, 2)
    end

    # Test: Event bus continues processing after handler error
    def test_dispatching_continues_after_error
      subscribe_to(UserRegistered) { |event| raise StandardError, "Handler failed" }
        .publish_event(UserRegistered.new(id: 1, email: "first@example.com"))
        .publish_event(UserRegistered.new(id: 2, email: "second@example.com"))
        .wait_for_handlers_to_complete(UserRegistered, 2)
        .assert_handler_error_captured(UserRegistered, StandardError)
    end

    # Test: Multiple handlers execute even when some fail
    def test_all_handlers_execute_despite_errors
      subscribe_to(OrderPlaced) { |event| } # Success
        .subscribe_to(OrderPlaced) { |event| raise StandardError } # Fails
        .subscribe_to(OrderPlaced) { |event| } # Success
        .subscribe_to(OrderPlaced) { |event| raise ArgumentError } # Fails
        .publish_event(OrderPlaced.new(order_id: 1, total: 100.0))
        .wait_for_handlers_to_complete(OrderPlaced, 4)
        .assert_all_handlers_executed_despite_errors(OrderPlaced, 4)
    end

    # Test: Errors from concurrent handler execution are isolated
    def test_concurrent_handler_error_isolation
      subscribe_to(PaymentProcessed) { |event| sleep 0.1 } # Slow success
        .subscribe_to(PaymentProcessed) { |event| raise StandardError } # Fast fail
        .subscribe_to(PaymentProcessed) { |event| } # Fast success
        .publish_event(PaymentProcessed.new(order_id: 1, amount: 50.0))
        .wait_for_handlers_to_complete(PaymentProcessed, 3)
        .assert_other_handlers_executed(PaymentProcessed, 2)
    end

    # Test: Handler errors are captured for observability
    def test_handler_errors_are_captured
      subscribe_to(UserRegistered) { |event| raise ArgumentError, "Invalid data" }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .wait_for_handlers_to_complete(UserRegistered, 1)
        .assert_handler_error_captured(UserRegistered, ArgumentError)
    end

    # Test: Different error types are captured correctly
    def test_different_error_types_captured
      subscribe_to(OrderPlaced) { |event| raise StandardError, "Standard error" }
        .subscribe_to(OrderPlaced) { |event| raise ArgumentError, "Argument error" }
        .publish_event(OrderPlaced.new(order_id: 1, total: 100.0))
        .wait_for_handlers_to_complete(OrderPlaced, 2)
        .assert_handler_error_captured(OrderPlaced, StandardError)
        .assert_handler_error_captured(OrderPlaced, ArgumentError)
    end

    # Test: Block handlers with errors don't halt event processing
    def test_block_handler_errors_dont_halt_processing
      subscribe_to(UserRegistered) { |event| }
        .subscribe_to(UserRegistered) { |event| raise "Boom!" }
        .publish_events(
          UserRegistered.new(id: 1, email: "user1@example.com"),
          UserRegistered.new(id: 2, email: "user2@example.com"),
          UserRegistered.new(id: 3, email: "user3@example.com")
        )
        .wait_for_handlers_to_complete(UserRegistered, 6) # 3 events × 2 handlers
        .assert_other_handlers_executed(UserRegistered, 3) # Only successful handlers
        .assert_handler_error_captured(UserRegistered, RuntimeError) # Errors captured
    end
  end
end
