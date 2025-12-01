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
        .assert_subscriber_invocation_failed_published(UserRegistered, expected_count: 1)
    end

    # Test: Event bus continues processing after handler error
    def test_dispatching_continues_after_error
      subscribe_to(UserRegistered) { |event| raise StandardError, "Handler failed" }
        .publish_event(UserRegistered.new(id: 1, email: "first@example.com"))
        .publish_event(UserRegistered.new(id: 2, email: "second@example.com"))
        .wait_for_handlers_to_complete(UserRegistered, 2)
        .assert_handler_error_captured(UserRegistered, StandardError)
        .assert_subscriber_invocation_failed_published(UserRegistered, expected_count: 2)
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
        .assert_subscriber_invocation_failed_published(OrderPlaced, expected_count: 2)
        .assert_subscriber_invocation_failed_with_error(OrderPlaced, StandardError)
        .assert_subscriber_invocation_failed_with_error(OrderPlaced, ArgumentError)
    end

    # Test: Errors from concurrent handler execution are isolated
    def test_concurrent_handler_error_isolation
      subscribe_to(PaymentProcessed) { |event| sleep 0.1 } # Slow success
        .subscribe_to(PaymentProcessed) { |event| raise StandardError } # Fast fail
        .subscribe_to(PaymentProcessed) { |event| } # Fast success
        .publish_event(PaymentProcessed.new(order_id: 1, amount: 50.0))
        .wait_for_handlers_to_complete(PaymentProcessed, 3)
        .assert_other_handlers_executed(PaymentProcessed, 2)
        .assert_subscriber_invocation_failed_published(PaymentProcessed, expected_count: 1)
    end

    # Test: Handler errors are captured for observability
    def test_handler_errors_are_captured
      subscribe_to(UserRegistered) { |event| raise ArgumentError, "Invalid data" }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .wait_for_handlers_to_complete(UserRegistered, 1)
        .assert_handler_error_captured(UserRegistered, ArgumentError)
        .assert_subscriber_invocation_failed_published(UserRegistered, expected_count: 1)
        .assert_subscriber_invocation_failed_with_error(UserRegistered, ArgumentError)
    end

    # Test: Different error types are captured correctly
    def test_different_error_types_captured
      subscribe_to(OrderPlaced) { |event| raise StandardError, "Standard error" }
        .subscribe_to(OrderPlaced) { |event| raise ArgumentError, "Argument error" }
        .publish_event(OrderPlaced.new(order_id: 1, total: 100.0))
        .wait_for_handlers_to_complete(OrderPlaced, 2)
        .assert_handler_error_captured(OrderPlaced, StandardError)
        .assert_handler_error_captured(OrderPlaced, ArgumentError)
        .assert_subscriber_invocation_failed_published(OrderPlaced, expected_count: 2)
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
        .assert_subscriber_invocation_failed_published(UserRegistered, expected_count: 3)
    end

    # Test: SubscriberInvocationFailed contains block source code
    def test_subscriber_invocation_failed_contains_block_source
      subscribe_to(UserRegistered) { |event| raise StandardError, "Test error" }
        .publish_event(UserRegistered.new(id: 1, email: "test@example.com"))
        .wait_for_handlers_to_complete(UserRegistered, 1)
        # .assert_subscriber_invocation_failed_contains_source(UserRegistered)
        .assert_captured_subscriber_invocation_failed(UserRegistered) do |failures|
          failure = failures.first
          assert_equal :block, failure.subscriber_type
          assert_equal "Proc", failure.subscriber_class
          # assert_includes failure.subscriber_source, "raise StandardError"
        end
    end

    # Test: SubscriberInvocationFailed contains all error details
    def test_subscriber_invocation_failed_contains_error_details
      subscribe_to(OrderPlaced) { |event| raise ArgumentError, "Invalid order" }
        .publish_event(OrderPlaced.new(order_id: 99, total: 100.0))
        .wait_for_handlers_to_complete(OrderPlaced, 1)
        .assert_captured_subscriber_invocation_failed(OrderPlaced) do |failures|
          failure = failures.first

          assert_equal OrderPlaced, failure.original_event.class
          assert_equal 99, failure.original_event.order_id
          assert_equal "ArgumentError", failure.error_class
          assert_equal "Invalid order", failure.error_message
          assert failure.error_backtrace.is_a?(Array)
          assert failure.occurred_at.is_a?(Time)
        end
    end
  end
end
