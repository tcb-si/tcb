# frozen_string_literal: true

module TCB
  class EventStore
    EventStreamEnvelope = Data.define(
      :event,
      :event_id,
      :stream_id,
      :version,
      :occurred_at
    )
  end
end