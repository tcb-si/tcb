# frozen_string_literal: true

module TCB
  EventBusShutdown = Data.define(
    :status,           # :initiated, :completed, :timeout_exceeded
    :drain_requested,  # true/false - was drain requested?
    :timeout_seconds,  # timeout value used
    :events_drained,   # number of events processed during shutdown
    :occurred_at       # timestamp
  )
end
