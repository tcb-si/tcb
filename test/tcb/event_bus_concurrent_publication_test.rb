require_relative '../test_helper'

module TCB
  class EventBusConcurrentPublicationTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Handle concurrent publications safely
    def test_concurrent_publications_are_thread_safe
      subscribe_to(UserRegistered) { |event| }
        .publish_concurrently(10) { |i| UserRegistered.new(id: i, email: "user#{i}@example.com") }
        .assert_all_events_received(UserRegistered, 10)
        .assert_unique_events_received(UserRegistered, (0..9).to_a)
    end

    # Test: High volume concurrent publications
    def test_high_volume_concurrent_publications
      subscribe_to(OrderPlaced) { |event| }
        .publish_concurrently_from_threads(10, 10) do |thread_id, i|
          order_id = thread_id * 10 + i
          OrderPlaced.new(order_id: order_id, total: 10.0)
        end
        .assert_all_events_received(OrderPlaced, 100)
    end

    # Test: Concurrent publications with different event types
    def test_concurrent_publications_different_event_types
      subscribe_to(UserRegistered) { |event| }
        .subscribe_to(OrderPlaced) { |event| }
        .publish_concurrently(5) { |i| UserRegistered.new(id: i, email: "user#{i}@example.com") }
        .publish_concurrently(5) { |i| OrderPlaced.new(order_id: i, total: i * 10.0) }
        .assert_all_events_received(UserRegistered, 5)
        .assert_all_events_received(OrderPlaced, 5)
    end

    # Test: Queue remains consistent under concurrent load
    def test_queue_consistency_under_concurrent_load
      subscribe_to(PaymentProcessed) { |event| }
        .publish_concurrently_from_threads(20, 3) do |thread_id, i|
          order_id = thread_id * 3 + i
          PaymentProcessed.new(order_id: order_id, amount: 10.0)
        end
        .assert_all_events_received(PaymentProcessed, 60)
        .assert_captured_events(PaymentProcessed) do |events|
          expected_ids = (0...60).to_a
          actual_ids = events.map(&:order_id).sort
          assert_equal expected_ids, actual_ids, "All events should be processed without loss"
        end
    end

    # Test: No events lost during concurrent publishing
    def test_no_event_loss_during_concurrent_publishing
      subscribe_to(UserRegistered) { |event| }
        .subscribe_to(UserRegistered) { |event| }
        .subscribe_to(UserRegistered) { |event| }
        .publish_concurrently(50) { |i| UserRegistered.new(id: i, email: "test#{i}@example.com") }
        .assert_no_event_loss(UserRegistered, 150)
    end
  end
end
