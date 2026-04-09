# frozen_string_literal: true

module TCB
  module Publishes
    def publish(*events)
      TCB.config.event_bus.publish(*events)
      events
    end
  end
end
