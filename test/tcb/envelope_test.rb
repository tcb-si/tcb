require_relative '../test_helper'

module TCB
  class EnvelopeTest < Minitest::Test

    def test_envelope_is_alias_for_event_stream_envelope
      assert_equal TCB::EventStore::EventStreamEnvelope, TCB::Envelope
    end

    def test_envelope_can_be_instantiated_directly
      envelope = TCB::Envelope.new(
        event:       OrderPlaced.new(order_id: 1, total: 100.0),
        event_id:    "abc-123",
        stream_id:   "orders|1",
        version:     1,
        occurred_at: Time.now
      )
      assert_instance_of TCB::EventStore::EventStreamEnvelope, envelope
    end
  end
end
