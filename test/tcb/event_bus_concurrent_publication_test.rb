require_relative '../test_helper'

module TCB
  class EventBusConcurrentPublicationTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus
    end

    # Test: Handle concurrent publications safely
    def test_concurrent_publications_are_thread_safe
      received_events = []
      mutex = Mutex.new
      
      subscribe_to(UserRegistered) do |event|
        mutex.synchronize { received_events << event }
      end
      
      # Publish from 10 threads concurrently
      threads = 10.times.map do |i|
        Thread.new do
          publish_event(UserRegistered.new(id: i, email: "user#{i}@example.com"))
        end
      end
      
      threads.each(&:join)
      sleep 0.2 # Wait for dispatch
      
      assert_equal 10, received_events.size, 
        "All 10 events should be received"
      
      # Verify all unique events received
      received_ids = received_events.map(&:id).sort
      assert_equal (0..9).to_a, received_ids,
        "All events should be unique and received"
    end

    # Test: High volume concurrent publications
    def test_high_volume_concurrent_publications
      event_count = 100
      received_count = 0
      mutex = Mutex.new
      
      subscribe_to(OrderPlaced) do |event|
        mutex.synchronize { received_count += 1 }
      end
      
      # Publish 100 events from 10 threads
      threads = 10.times.map do |thread_id|
        Thread.new do
          10.times do |i|
            order_id = thread_id * 10 + i
            publish_event(OrderPlaced.new(order_id: order_id, total: 10.0))
          end
        end
      end
      
      threads.each(&:join)
      sleep 0.5 # Wait for all dispatches
      
      assert_equal event_count, received_count,
        "All #{event_count} events should be received"
    end

    # Test: Concurrent publications with different event types
    def test_concurrent_publications_different_event_types
      user_events = []
      order_events = []
      user_mutex = Mutex.new
      order_mutex = Mutex.new
      
      subscribe_to(UserRegistered) do |event|
        user_mutex.synchronize { user_events << event }
      end
      
      subscribe_to(OrderPlaced) do |event|
        order_mutex.synchronize { order_events << event }
      end
      
      # Mix different event types from multiple threads
      threads = []
      
      5.times do |i|
        threads << Thread.new do
          publish_event(UserRegistered.new(id: i, email: "user#{i}@example.com"))
        end
        
        threads << Thread.new do
          publish_event(OrderPlaced.new(order_id: i, total: i * 10.0))
        end
      end
      
      threads.each(&:join)
      sleep 0.3
      
      assert_equal 5, user_events.size, "Should receive 5 user events"
      assert_equal 5, order_events.size, "Should receive 5 order events"
    end

    # Test: Queue remains consistent under concurrent load
    def test_queue_consistency_under_concurrent_load
      processed_events = []
      mutex = Mutex.new
      
      subscribe_to(PaymentProcessed) do |event|
        mutex.synchronize { processed_events << event.order_id }
      end
      
      # Rapid-fire publications from multiple threads
      expected_order_ids = []
      threads = 20.times.map do |i|
        Thread.new do
          3.times do |j|
            order_id = i * 3 + j
            expected_order_ids << order_id
            publish_event(PaymentProcessed.new(order_id: order_id, amount: 10.0))
            sleep 0.001 # Tiny delay to stress test
          end
        end
      end
      
      threads.each(&:join)
      sleep 1.0 # Wait for all to process
      
      assert_equal 60, processed_events.size, "Should process all 60 events"
      assert_equal expected_order_ids.sort, processed_events.sort,
        "All events should be processed without loss"
    end

    # Test: No events lost during concurrent publishing
    def test_no_event_loss_during_concurrent_publishing
      total_received = 0
      mutex = Mutex.new
      
      # Multiple handlers to increase load
      3.times do
        subscribe_to(UserRegistered) do |event|
          mutex.synchronize { total_received += 1 }
        end
      end
      
      # Publish 50 events concurrently
      threads = 50.times.map do |i|
        Thread.new do
          publish_event(UserRegistered.new(id: i, email: "test#{i}@example.com"))
        end
      end
      
      threads.each(&:join)
      sleep 0.8
      
      # 50 events * 3 handlers = 150 total invocations
      assert_equal 150, total_received,
        "All handler invocations should complete (expected 150, got #{total_received})"
    end
  end
end
