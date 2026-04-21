require_relative '../test_helper'

module TCB
  class EventBusQueuePressureTest < Minitest::Test
    include EventBusDSL

    def setup
      create_event_bus(max_queue_size: 10, high_water_mark: 8)
    end

    def teardown
      TCB.reset!
    end

    def test_queue_pressure_event_published_when_high_water_mark_reached
      fill_queue_and_block_dispatcher(UserRegistered)
        .fill_queue(UserRegistered, count: 9)
        .release_dispatcher(count: 10)
        .assert_event_delivered_to_handler(TCB::EventBusQueuePressure)
    end

    def test_queue_pressure_event_published_only_once_per_crossing
      fill_queue_and_block_dispatcher(UserRegistered)
        .fill_queue(UserRegistered, count: 10)
        .release_dispatcher(count: 11)
        .assert_handler_called_times(TCB::EventBusQueuePressure, 1)
    end

    def test_queue_pressure_not_published_without_high_water_mark
      create_event_bus(max_queue_size: 10)
      fill_queue_and_block_dispatcher(UserRegistered)
        .fill_queue(UserRegistered, count: 10)
        .release_dispatcher
        .assert_event_not_delivered(TCB::EventBusQueuePressure)
    end
  end
end
