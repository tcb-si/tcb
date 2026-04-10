module TCB
  ConfigurationError = Class.new(StandardError)

  class Configuration
    def initialize
      @persist_registrations = []
    end

    def persist_registrations
      @persist_registrations
    end

    def event_bus=(bus)
      @event_bus = bus
    end

    def event_bus
      @event_bus || raise(ConfigurationError, "TCB event_bus is not configured. Call TCB.configure { |c| c.event_bus = TCB::EventBus.new }")
    end

    def event_store=(store)
      @event_store = store
    end

    def event_store
      @event_store
    end

    def event_handlers=(modules)
      @event_handlers = modules
      flush_event_handlers
      flush_persist_registrations
    end

    def event_handlers
      @event_handlers || []
    end

    private

    def flush_event_handlers
      @event_handlers.each do |mod|
        mod.event_handler_registrations.each do |registration|
          registration.handlers.each do |handler|
            event_bus.subscribe(registration.event_class) do |event|
              handler.new.call(event)
            end
          end
        end
      end
    end

    def flush_persist_registrations
      @persist_registrations = []
      @event_handlers.each do |mod|
        context = StreamId.context_from_module(mod)
        mod.persist_registrations.each do |registration|
          @persist_registrations << registration.with(context: context)
        end
      end
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