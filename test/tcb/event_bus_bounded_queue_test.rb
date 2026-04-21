require_relative '../test_helper'

module TCB
  class EventBusBoundedQueueTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus(max_queue_size: 1)
    end

    def teardown
      TCB.reset!
    end

    def test_bounded_queue_accepts_events_normally
      subscribe_to(UserRegistered) { |_| }
        .publish_event(UserRegistered.new(id: 1, email: "a@b.com"))
        .assert_event_delivered_to_handler(UserRegistered)
    end

    def test_publish_blocks_caller_when_queue_is_full
      fill_queue_and_block_dispatcher(UserRegistered)
        .fill_queue(UserRegistered, count: 2)
        .assert_next_publish_blocks(UserRegistered.new(id: 99, email: "blocked@b.com"))
        .release_dispatcher
    end
  end
end
