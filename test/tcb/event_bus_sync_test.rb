require_relative '../test_helper'

module TCB
  class EventBusSyncTest < Minitest::Test
    include EventBusDSL

    def setup
      create_synchronous_bus
    end

    # Test: Handler results immediately available after publish — no poll_assert needed
    def test_handler_results_immediately_available
      result = nil
      subscribe_to(UserRegistered) { |event| result = event.id }
        .publish_event(UserRegistered.new(id: 1, email: "sync@example.com"))

      assert_equal 1, result
    end

    # Test: Publish executes handler in caller thread
    def test_publish_executes_in_caller_thread
      handler_thread_id = nil
      subscribe_to(UserRegistered) { |event| handler_thread_id = Thread.current.object_id }
        .publish_event(UserRegistered.new(id: 1, email: "sync@example.com"))

      assert_equal Thread.current.object_id, handler_thread_id
    end

    # Test: Failing handler does not prevent subsequent handlers from executing
    def test_error_isolation_continues_remaining_handlers
      results = []
      subscribe_to(UserRegistered) { |_| raise "boom" }
        .subscribe_to(UserRegistered) { |event| results << event.id }
        .publish_event(UserRegistered.new(id: 1, email: "sync@example.com"))

      assert_equal [1], results
    end

    # Test: SubscriberInvocationFailed dispatched synchronously on handler error
    def test_subscriber_invocation_failed_dispatched_on_error
      subscribe_to(UserRegistered) { |_| raise "boom" }
        .publish_event(UserRegistered.new(id: 1, email: "sync@example.com"))
        .assert_subscriber_invocation_failed_published(UserRegistered)
    end

    # Test: force_shutdown na sync bus je safe — ni dispatcher threada
    def test_force_shutdown_on_sync_bus_is_safe
      assert_silent { force_shutdown_bus }
      assert_dispatcher_thread_dead
    end
  end
end