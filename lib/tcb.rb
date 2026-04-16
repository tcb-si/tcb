# frozen_string_literal: true

require_relative "tcb/minitest_helpers"
require_relative "tcb/domain_context"
require_relative "tcb/event_query"
require_relative "tcb/event_store/active_record"
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
require_relative "tcb/version"

module TCB
  Envelope = EventStore::EventStreamEnvelope

  def self.record(events_from: [], events: [], within: nil, &block)
    Record.call(
      events_from: events_from,
      events: events,
      within: within,
      store: config.event_store,
      registrations: config.persist_registrations,
      &block
    )
  end

  def self.read(domain_module)
    EventQuery.new(
      store: config.event_store,
      context: DomainContext.from_module(domain_module).to_s
    )
  end

  def self.reset!
    config.reset_handlers!
    config.event_store.reset! if config.event_store.respond_to?(:reset!)
  end
end