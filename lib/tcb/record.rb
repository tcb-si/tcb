# frozen_string_literal: true

module TCB
  class Record
    def self.call(events_from:, events:, within:, store:, registrations:, &block)
      raise ArgumentError, "events_from: or events: must be provided" if events_from.empty? && events.empty?
      new(events_from: events_from, events: events, store: store, registrations: registrations)
        .call(within: within, &block)
    end

    def initialize(events_from:, events:, store:, registrations:)
      @events_from = events_from
      @events = events
      @store = store
      @registrations = registrations
    end

    def call(within:, &block)
      if within
        within.transaction { execute(&block) }
      else
        execute(&block)
      end
    end

    private

    def execute(&block)
      block.call if block
      events  = @events_from.flat_map(&:pull_recorded_events)
      events += @events
      persist(events)
      events
    rescue
      @events_from.each(&:pull_recorded_events)
      raise
    end

    def persist(events)
      return unless @store

      grouped = Hash.new { |h, k| h[k] = [] }

      events.each do |event|
        registration = @registrations.find { |r| r.event_classes.include?(event.class) }
        next unless registration

        stream_id = StreamId.build(registration.context, event.public_send(registration.stream_id_from_event))
        grouped[stream_id.to_s] << event
      end

      grouped.each { |stream_id, grouped_events| @store.append(stream_id: stream_id, events: grouped_events) }
    end
  end
end
