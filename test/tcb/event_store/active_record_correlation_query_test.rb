# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/active_record_setup"

module TCB
  class EventStore::ActiveRecordCorrelationQueryTest < Minitest::Test

    def setup
      TCB.reset!
      Orders::EventRecord.delete_all
      TCB.configure do |c|
        c.event_bus = TCB::EventBus.new(sync: true)
        c.extra_serialization_classes = [OrderPlaced, PaymentProcessed]
      end
      @store = TCB::EventStore::ActiveRecord.new
    end

    def teardown
      Orders::EventRecord.delete_all
      TCB.reset!
    end

    def test_read_by_correlation_returns_matching_envelopes
      @store.append(stream_id: "orders|1", events: [OrderPlaced.new(order_id: 1, total: 100.0)], correlation_id: "req-abc")
      @store.append(stream_id: "orders|2", events: [OrderPlaced.new(order_id: 2, total: 200.0)], correlation_id: "req-xyz")

      results = @store.read_by_correlation("req-abc", context: "orders")

      assert_equal 1, results.size
      assert_equal "req-abc", results.first.correlation_id
    end

    def test_read_by_correlation_returns_empty_for_unknown_id
      results = @store.read_by_correlation("unknown", context: "orders")
      assert_equal [], results
    end

    def test_read_by_correlation_filters_by_occurred_after
      t1 = Time.utc(2024, 1, 1, 12, 0, 0)
      t2 = Time.utc(2024, 1, 1, 13, 0, 0)

      @store.append(stream_id: "orders|1", events: [OrderPlaced.new(order_id: 1, total: 100.0)], correlation_id: "req-abc", occurred_at: t1)
      @store.append(stream_id: "orders|2", events: [OrderPlaced.new(order_id: 2, total: 200.0)], correlation_id: "req-abc", occurred_at: t2)

      results = @store.read_by_correlation("req-abc", context: "orders", occurred_after: Time.utc(2024, 1, 1, 12, 30, 0))

      assert_equal 1, results.size
      assert_instance_of OrderPlaced, results.first.event
      assert_equal 2, results.first.event.order_id
    end

    def test_read_by_correlation_filters_by_occurred_before
      t1 = Time.utc(2024, 1, 1, 12, 0, 0)
      t2 = Time.utc(2024, 1, 1, 13, 0, 0)

      @store.append(stream_id: "orders|1", events: [OrderPlaced.new(order_id: 1, total: 100.0)], correlation_id: "req-abc", occurred_at: t1)
      @store.append(stream_id: "orders|2", events: [OrderPlaced.new(order_id: 2, total: 200.0)], correlation_id: "req-abc", occurred_at: t2)

      results = @store.read_by_correlation("req-abc", context: "orders", occurred_before: Time.utc(2024, 1, 1, 12, 30, 0))

      assert_equal 1, results.size
      assert_instance_of OrderPlaced, results.first.event
      assert_equal 1, results.first.event.order_id
    end
  end
end
