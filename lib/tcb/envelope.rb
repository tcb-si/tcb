# frozen_string_literal: true

require "securerandom"

module TCB
  Envelope = Data.define(
    :event,
    :event_id,
    :stream_id,
    :version,
    :occurred_at,
    :correlation_id,
    :causation_id
  ) do
    def self.wrap(event, correlation_id: nil, causation_id: nil)
      new(
        event:          event,
        event_id:       SecureRandom.uuid,
        stream_id:      nil,
        version:        nil,
        occurred_at:    Time.now,
        correlation_id: correlation_id,
        causation_id:   causation_id
      )
    end

    def self.coerce(event_or_envelope)
      event_or_envelope.is_a?(self) ? event_or_envelope : wrap(event_or_envelope)
    end
  end
end
