module TCB
  def self.publish(*events)
    events.each { |event| config.event_bus.publish(event) }
    events
  end
end