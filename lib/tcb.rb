# frozen_string_literal: true

require_relative "tcb/envelope"
require_relative "tcb/minitest_helpers"
require_relative "tcb/domain_context"
require_relative "tcb/event_query"
require_relative "tcb/event_store/active_record"
require_relative "tcb/event_store/in_memory"
require_relative "tcb/stream_id"
require_relative "tcb/handles_events"
require_relative "tcb/handles_commands"
require_relative "tcb/records_events"
require_relative "tcb/record"
require_relative "tcb/configuration"
require_relative "tcb/publish"
require_relative "tcb/command_bus"
require_relative "tcb/subscriber_metadata_extractor"
require_relative "tcb/subscriber_invocation_failed"
require_relative "tcb/event_bus/queue_pressure_monitor"
require_relative "tcb/event_bus_queue_pressure"
require_relative "tcb/event_bus_shutdown"
require_relative "tcb/domain"
require_relative "tcb/event_bus"
require_relative "tcb/version"

module TCB

  def self.domain_modules=(modules)
    @domain_modules = modules
  end

  def self.domain_modules
    @domain_modules || []
  end

  def self.configure(&block)
    yield config
    config.domain_modules = @domain_modules || []
    config.permitted_serialization_classes
    config.freeze
  end

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

  def self.config
    @config ||= Configuration.new
  end

  def self.configured?
    !!@config && @config.event_bus_configured?
  end

  def self.reset!(graceful_shutdown_time: nil)
    if configured?
      graceful_shutdown_time ?
        @config.event_bus.shutdown(drain: true, timeout: graceful_shutdown_time) :
        @config.event_bus.force_shutdown
    end
    @config = nil
  end
end
