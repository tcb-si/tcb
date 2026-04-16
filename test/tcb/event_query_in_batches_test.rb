# frozen_string_literal: true

require_relative '../test_helper'

module TCB
  class EventQueryInBatchesTest < Minitest::Test

    module Orders
      include TCB::HandlesEvents

      persist events(
        OrderPlaced,
        PaymentProcessed,
        stream_id_from_event: :order_id
      )
    end

    def setup
      TCB.instance_variable_set(:@config, nil)
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new
        c.event_store = TCB::EventStore::InMemory.new
        c.event_handlers = [Orders]
      end

      @store = TCB.config.event_store

      # Append 25 events to stream
      25.times do |i|
        @store.append(
          stream_id: "tcb/event_query_in_batches_test/orders|42",
          events: [OrderPlaced.new(order_id: 42, total: (i + 1) * 10.0)]
        )
      end
    end

    def teardown
      TCB.config.event_bus.force_shutdown
      TCB.instance_variable_set(:@config, nil)
    end

    # Test: in_batches yields all events in correct batch sizes
    def test_in_batches_yields_all_events
      batches = []
      TCB.read(Orders).stream(42).in_batches(of: 10) { |batch| batches << batch }

      assert_equal 3, batches.size
      assert_equal 10, batches[0].size
      assert_equal 10, batches[1].size
      assert_equal 5,  batches[2].size
    end

    # Test: in_batches yields TCB::Envelope objects
    def test_in_batches_yields_envelopes
      TCB.read(Orders).stream(42).in_batches(of: 10) do |batch|
        batch.each { |envelope| assert_instance_of TCB::Envelope, envelope }
      end
    end

    # Test: in_batches covers all events without duplicates
    def test_in_batches_covers_all_events_without_duplicates
      versions = []
      TCB.read(Orders).stream(42).in_batches(of: 10) { |batch| versions.concat(batch.map(&:version)) }

      assert_equal 25, versions.size
      assert_equal (1..25).to_a, versions.sort
    end

    # Test: from_version limits start
    def test_in_batches_with_from_version
      batches = []
      TCB.read(Orders).stream(42).in_batches(of: 10, from_version: 11) { |batch| batches << batch }

      assert_equal 2, batches.size
      assert_equal 10, batches[0].size
      assert_equal 5,  batches[1].size
      assert_equal 11, batches[0].first.version
    end

    # Test: to_version limits end
    def test_in_batches_with_to_version
      batches = []
      TCB.read(Orders).stream(42).in_batches(of: 10, to_version: 20) { |batch| batches << batch }

      assert_equal 2, batches.size
      assert_equal 10, batches[0].size
      assert_equal 10, batches[1].size
      assert_equal 20, batches[1].last.version
    end

    # Test: from_version and to_version together
    def test_in_batches_with_from_and_to_version
      versions = []
      TCB.read(Orders).stream(42).in_batches(of: 5, from_version: 6, to_version: 15) do |batch|
        versions.concat(batch.map(&:version))
      end

      assert_equal (6..15).to_a, versions
    end

    # Test: without block returns Enumerator
    def test_in_batches_without_block_returns_enumerator
      result = TCB.read(Orders).stream(42).in_batches(of: 10)
      assert_instance_of Enumerator, result
    end

    # Test: empty stream yields no batches
    def test_in_batches_empty_stream_yields_no_batches
      batches = []
      TCB.read(Orders).stream(999).in_batches(of: 10) { |batch| batches << batch }
      assert_equal [], batches
    end

    # Test: batch size larger than total events yields one batch
    def test_in_batches_larger_than_stream
      batches = []
      TCB.read(Orders).stream(42).in_batches(of: 100) { |batch| batches << batch }

      assert_equal 1, batches.size
      assert_equal 25, batches[0].size
    end

    # Test: in_batches without stream yields nothing
    def test_in_batches_without_stream_yields_nothing
      batches = []
      TCB.read(Orders).in_batches(of: 10) { |batch| batches << batch }
      assert_equal [], batches
    end
  end
end
