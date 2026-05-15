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
      @event_bus ||
        raise(
          ConfigurationError,
          "TCB event_bus is not configured. Call TCB.configure { |c| c.event_bus = TCB::EventBus.new }"
        )
    end

    def event_store=(store)
      @event_store = store
    end

    def event_store
      @event_store
    end

    def domain_modules=(modules)
      @domain_modules = modules
      flush_domain_modules
      flush_command_handlers
      flush_persist_registrations
      flush_outbox_registrations
    end

    def domain_modules
      @domain_modules || []
    end

    def command_handler(command_class)
      @command_handlers ||= {}
      @command_handlers[command_class]
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

    def event_bus_configured?
      !!@event_bus
    end

    private

    def flush_domain_modules
      @domain_modules.each do |domain_module|
        next unless domain_module.respond_to?(:event_handler_registrations)

        domain_module.event_handler_registrations.each do |registration|
          registration.handlers.each do |handler|
            event_bus.subscribe(registration.event_class) do |envelope|
              Thread.current[:tcb_correlation_id] = envelope.correlation_id
              Thread.current[:tcb_causation_id]   = envelope.event_id
              handler.new.call(envelope.event)
            ensure
              Thread.current[:tcb_correlation_id] = nil
              Thread.current[:tcb_causation_id]   = nil
            end
          end
        end
      end
    end

    def flush_command_handlers
      @command_handlers = {}
      @domain_modules.each do |domain_module|
        next unless domain_module.respond_to?(:command_handler_registrations)

        domain_module.command_handler_registrations.each do |reg|
          @command_handlers[reg.command_class] = reg.handler
        end
      end
    end

    def flush_persist_registrations
      @persist_registrations = []
      @domain_modules.each do |domain_module|
        next unless domain_module.respond_to?(:persist_registrations)
        next unless domain_module.persist_registrations.any?

        context = DomainContext.from_module(domain_module).to_s
        domain_module.persist_registrations.each do |registration|
          @persist_registrations << registration.with(context: context)
        end
        define_event_record_for(domain_module)
      end
    end

    def flush_outbox_registrations
      @domain_modules.each do |domain_module|
        next unless domain_module.respond_to?(:outbox_registrations)
        next unless domain_module.outbox_registrations.any?

        persisted_event_classes = domain_module.persist_registrations.flat_map(&:event_classes)
        outbox_event_classes = domain_module.outbox_registrations.map(&:event_class).uniq

        outbox_event_classes.each do |event_class|
          unless persisted_event_classes.include?(event_class)
            raise ConfigurationError,
              "#{event_class} has ensure_reaction in #{domain_module} but is not persisted. Add a persist registration."
          end
        end
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
end
