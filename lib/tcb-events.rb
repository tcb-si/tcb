# frozen_string_literal: true

require_relative "tcb/subscriber_metadata_extractor"
require_relative "tcb/subscriber_invocation_failed"
require_relative "tcb/event_bus_shutdown"
require_relative "tcb/event_bus"

module TCB
  module Events
    VERSION = "0.3.56"
  end
end
