
module TCB
  CommandHandlerNotFound = Class.new(StandardError)

  def self.dispatch(command)
    validate!(command)
    handler = resolve_handler(command)
    handler.new.call(command)
  end

  def self.validate!(command)
    unless command.respond_to?(:validate!)
      raise NotImplementedError, "#{command.class} must implement validate!"
    end
    command.validate!
  end
  private_class_method :validate!

  def self.resolve_handler(command)
    handler = config.command_handler(command.class)
    raise CommandHandlerNotFound, "No handler registered for #{command.class.name}" unless handler

    handler
  end
  private_class_method :resolve_handler
end