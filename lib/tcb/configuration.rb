module TCB
  ConfigurationError = Class.new(StandardError)

  class Configuration
    def event_bus=(bus)
      @event_bus = bus
    end

    def event_bus
      @event_bus || raise(ConfigurationError, "TCB event_bus is not configured. Call TCB.configure { |c| c.event_bus = TCB::EventBus.new }")
    end
  end

  def self.configure
    yield config
    config.freeze
  end

  def self.config
    @config ||= Configuration.new
  end
end