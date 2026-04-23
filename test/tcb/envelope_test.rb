require_relative '../test_helper'

module TCB
  class EnvelopeTest < Minitest::Test

    def test_envelope_has_correlation_id
      envelope = TCB::Envelope.new(
        event: OrderPlaced.new(order_id: 1, total: 100.0),
        event_id: "abc-123", stream_id: "orders|1",
        version: 1, occurred_at: Time.now,
        correlation_id: "corr-xyz", causation_id: nil
      )
      assert_equal "corr-xyz", envelope.correlation_id
      assert_nil envelope.causation_id
    end

    def test_envelope_correlation_and_causation_default_to_nil
      envelope = TCB::Envelope.new(
        event: OrderPlaced.new(order_id: 1, total: 100.0),
        event_id: "abc-123", stream_id: "orders|1",
        version: 1, occurred_at: Time.now,
        correlation_id: nil, causation_id: nil
      )
      assert_nil envelope.correlation_id
      assert_nil envelope.causation_id
    end
  end
end
