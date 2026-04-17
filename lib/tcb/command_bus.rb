
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
    handler_name = "#{command.class.name}Handler"
    Object.const_get(handler_name)
  rescue NameError
    raise CommandHandlerNotFound,
      "No handler found for #{command.class.name}, expected #{command.class.name}Handler"
  end
  private_class_method :resolve_handler
end