module TCB
  module RecordsEvents
    def record(event)
      recorded_events_array << event
    end

    def recorded_events
      recorded_events_array.dup
    end

    def pull_recorded_events
      events = recorded_events_array.dup
      recorded_events_array.clear
      events
    end

    private

    def recorded_events_array
      @recorded_events ||= []
    end
  end
end
