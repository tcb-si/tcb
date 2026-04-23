require_relative '../../test_helper'

module TCB
  class EventStore::InMemoryTest < Minitest::Test

    def setup
      @store = EventStore::InMemory.new
    end

    # append
    def test_append_single_event
      @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: 42, total: 100.0)])
      envelopes = @store.read("orders|42")
      assert_equal 1, envelopes.size
    end

    def test_append_returns_envelopes
      envelopes = @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: 42, total: 100.0)])
      assert_equal 1, envelopes.size
      assert_instance_of TCB::Envelope, envelopes.first
    end

    def test_append_envelope_contains_original_event
      @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: 42, total: 100.0)])
      envelope = @store.read("orders|42").first
      assert_instance_of OrderPlaced, envelope.event
      assert_equal 42, envelope.event.order_id
    end

    def test_append_envelope_contains_stream_id
      @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: 42, total: 100.0)])
      envelope = @store.read("orders|42").first
      assert_equal "orders|42", envelope.stream_id
    end

    def test_append_envelope_contains_event_id
      @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: 42, total: 100.0)])
      envelope = @store.read("orders|42").first
      refute_nil envelope.event_id
      assert_instance_of String, envelope.event_id
    end

    def test_append_envelope_contains_occurred_at
      @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: 42, total: 100.0)])
      envelope = @store.read("orders|42").first
      assert_instance_of Time, envelope.occurred_at
    end

    def test_append_assigns_sequential_versions
      @store.append(stream_id: "orders|42", events: [
        OrderPlaced.new(order_id: 42, total: 100.0),
        PaymentProcessed.new(order_id: 42, amount: 100.0)
      ])
      envelopes = @store.read("orders|42")
      assert_equal 1, envelopes.first.version
      assert_equal 2, envelopes.last.version
    end

    def test_append_continues_version_sequence
      @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: 42, total: 100.0)])
      @store.append(stream_id: "orders|42", events: [PaymentProcessed.new(order_id: 42, amount: 100.0)])
      envelopes = @store.read("orders|42")
      assert_equal 1, envelopes.first.version
      assert_equal 2, envelopes.last.version
    end

    def test_append_assigns_unique_event_ids
      @store.append(stream_id: "orders|42", events: [
        OrderPlaced.new(order_id: 42, total: 100.0),
        PaymentProcessed.new(order_id: 42, amount: 100.0)
      ])
      envelopes = @store.read("orders|42")
      assert_equal 2, envelopes.map(&:event_id).uniq.size
    end

    def test_append_to_different_streams_are_independent
      @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: 42, total: 100.0)])
      @store.append(stream_id: "orders|99", events: [OrderPlaced.new(order_id: 99, total: 200.0)])
      assert_equal 1, @store.read("orders|42").size
      assert_equal 1, @store.read("orders|99").size
      assert_equal 1, @store.read("orders|42").first.version
      assert_equal 1, @store.read("orders|99").first.version
    end

    # read
    def test_read_returns_empty_array_for_unknown_stream
      assert_equal [], @store.read("orders|unknown")
    end

    def test_read_returns_envelopes_in_version_order
      @store.append(stream_id: "orders|42", events: [
        OrderPlaced.new(order_id: 42, total: 100.0),
        PaymentProcessed.new(order_id: 42, amount: 100.0)
      ])
      envelopes = @store.read("orders|42")
      assert_equal [1, 2], envelopes.map(&:version)
    end

    def test_read_from_version_returns_subsequent_events
      @store.append(stream_id: "orders|42", events: [
        OrderPlaced.new(order_id: 42, total: 100.0),
        PaymentProcessed.new(order_id: 42, amount: 100.0),
        UserRegistered.new(id: 1, email: "test@example.com")
      ])
      envelopes = @store.read("orders|42", from_version: 2)
      assert_equal 2, envelopes.size
      assert_equal [2, 3], envelopes.map(&:version)
    end

    def test_read_occurred_after_filters_by_time
      t1 = Time.now - 10
      t2 = Time.now

      @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: 42, total: 100.0)], occurred_at: t1)
      @store.append(stream_id: "orders|42", events: [PaymentProcessed.new(order_id: 42, amount: 100.0)], occurred_at: t2)

      envelopes = @store.read("orders|42", occurred_after: t1 + 1)
      assert_equal 1, envelopes.size
      assert_instance_of PaymentProcessed, envelopes.first.event
    end

    # thread safety
    def test_concurrent_appends_are_thread_safe
      threads = 10.times.map do |i|
        Thread.new do
          @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: i, total: i * 10.0)])
        end
      end
      threads.each(&:join)
      assert_equal 10, @store.read("orders|42").size
    end

    def test_concurrent_appends_assign_unique_versions
      threads = 10.times.map do |i|
        Thread.new do
          @store.append(stream_id: "orders|42", events: [OrderPlaced.new(order_id: i, total: i * 10.0)])
        end
      end
      threads.each(&:join)
      versions = @store.read("orders|42").map(&:version).sort
      assert_equal (1..10).to_a, versions
    end
  end
end
