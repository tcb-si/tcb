# frozen_string_literal: true

require_relative "tcb/records_events"
require_relative "tcb/record"
require_relative "tcb/configuration"
require_relative "tcb/publishes"
require_relative "tcb/command_bus"
require_relative "tcb/subscriber_metadata_extractor"
require_relative "tcb/subscriber_invocation_failed"
require_relative "tcb/event_bus_shutdown"
require_relative "tcb/event_bus"

module TCB
  VERSION = "0.4.56"
end