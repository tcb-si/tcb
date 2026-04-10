# frozen_string_literal: true

require_relative "tcb/event_store/event_stream_envelope"
require_relative "tcb/event_store/in_memory"
require_relative "tcb/stream_id"
require_relative "tcb/handles_events"
require_relative "tcb/records_events"
require_relative "tcb/record"
require_relative "tcb/configuration"
require_relative "tcb/publish"
require_relative "tcb/command_bus"
require_relative "tcb/subscriber_metadata_extractor"
require_relative "tcb/subscriber_invocation_failed"
require_relative "tcb/event_bus_shutdown"
require_relative "tcb/event_bus"

module TCB
  VERSION = "0.4.56"

  def self.record(aggregates:, within: nil, &block)
    Record.call(
      aggregates:   aggregates,
      within:       within,
      store:        config.event_store,
      registrations: config.persist_registrations,
      &block
    )
  end
end