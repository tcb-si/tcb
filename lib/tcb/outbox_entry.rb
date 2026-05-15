# frozen_string_literal: true

TCB::OutboxEntry = Data.define(
  :id,
  :event_id,
  :stream_id,
  :version,
  :handler_class,
  :status,
  :locked_at,
  :delivered_at,
  :error,
  :created_at
)
