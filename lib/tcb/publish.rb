module TCB
  def self.publish(*events_or_envelopes)
    events_or_envelopes.each do |e|
      envelope = TCB::Envelope.coerce(e)
      config.event_bus.publish(envelope)
    end
    events_or_envelopes
  end
end
