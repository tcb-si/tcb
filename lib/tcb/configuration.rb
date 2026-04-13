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

    def extra_serialization_classes=(classes)
      @extra_serialization_classes = classes
    end

    def extra_serialization_classes
      @extra_serialization_classes || []
    end

    def permitted_serialization_classes
      @permitted_serialization_classes ||= [
        Symbol, Time, Date, BigDecimal,
        *persist_registrations.flat_map(&:event_classes),
        *extra_serialization_classes
      ]
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
      @event_handlers.each do |domain_module|
        context = DomainContext.from_module(domain_module).to_s
        domain_module.persist_registrations.each do |registration|
          @persist_registrations << registration.with(context: context)
        end
        define_event_record_for(domain_module) if domain_module.persist_registrations.any?
      end
    end

    def define_event_record_for(domain_module)
      return if domain_module.const_defined?(:EventRecord, false)

      klass = Class.new(::ActiveRecord::Base) do
        self.table_name = DomainContext.from_module(domain_module).table_name
      end
      domain_module.const_set(:EventRecord, klass)
    end
  end

  def self.configure
    yield config
    config.permitted_serialization_classes
    config.freeze
  end

  def self.config
    @config ||= Configuration.new
  end
end