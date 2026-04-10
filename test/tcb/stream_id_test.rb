require_relative '../test_helper'

module TCB
  class StreamIdTest < Minitest::Test

    # build
    def test_build_creates_stream_id_with_context_and_id
      stream_id = StreamId.build("orders", "abc123")
      assert_equal "orders", stream_id.context
      assert_equal "abc123", stream_id.id
    end

    def test_build_normalizes_context_to_lowercase
      stream_id = StreamId.build("Orders", 42)
      assert_equal "orders", stream_id.context
      assert_equal "42", stream_id.id
    end

    def test_build_converts_id_to_string
      stream_id = StreamId.build("orders", 99)
      assert_equal "99", stream_id.id
    end

    def test_build_handles_namespaced_context
      stream_id = StreamId.build("day_recap/segment_builder", "abc123")
      assert_equal "day_recap/segment_builder", stream_id.context
    end

    # parse
    def test_parse_returns_stream_id_from_valid_string
      stream_id = StreamId.parse("orders|abc123")
      assert_instance_of StreamId, stream_id
      assert_equal "orders", stream_id.context
      assert_equal "abc123", stream_id.id
    end

    def test_parse_handles_id_with_pipes_split_on_first
      stream_id = StreamId.parse("orders|abc|123")
      assert_equal "orders", stream_id.context
      assert_equal "abc|123", stream_id.id
    end

    def test_parse_handles_namespaced_context
      stream_id = StreamId.parse("day_recap/segment_builder|abc123")
      assert_equal "day_recap/segment_builder", stream_id.context
      assert_equal "abc123", stream_id.id
    end

    def test_parse_raises_on_missing_separator
      assert_raises(ArgumentError) { StreamId.parse("invalid") }
    end

    def test_parse_raises_on_empty_context
      assert_raises(ArgumentError) { StreamId.parse("|abc123") }
    end

    def test_parse_raises_on_empty_id
      assert_raises(ArgumentError) { StreamId.parse("orders|") }
    end

    def test_parse_raises_on_empty_string
      assert_raises(ArgumentError) { StreamId.parse("") }
    end

    def test_parse_raises_on_nil
      assert_raises(ArgumentError) { StreamId.parse(nil) }
    end

    # to_s
    def test_to_s_returns_context_pipe_id
      stream_id = StreamId.build("orders", "abc123")
      assert_equal "orders|abc123", stream_id.to_s
    end

    # equality
    def test_equality_same_context_and_id
      assert_equal StreamId.build("orders", "abc123"), StreamId.parse("orders|abc123")
    end

    def test_equality_different_context
      refute_equal StreamId.build("orders", "abc123"), StreamId.build("payments", "abc123")
    end

    def test_equality_different_id
      refute_equal StreamId.build("orders", "abc123"), StreamId.build("orders", "def456")
    end

    module Orders
    end

    module Payments
      module Charges
      end
    end

    def test_from_module_infers_context_from_simple_module
      assert_equal "tcb/stream_id_test/orders", StreamId.context_from_module(Orders)
    end

    def test_from_module_infers_context_from_namespaced_module
      assert_equal "tcb/stream_id_test/payments/charges", StreamId.context_from_module(Payments::Charges)
    end
  end
end
