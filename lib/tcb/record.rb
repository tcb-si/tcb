# frozen_string_literal: true

module TCB
  class Record
    def self.call(events_from:, events:, within:, store:, registrations:, &block)
      raise ArgumentError, "events_from: or events: must be provided" if events_from.empty? && events.empty?

      new(
        events_from:    events_from,
        events:         events,
        store:          store,
        registrations:  registrations,
        correlation_id: Thread.current[:tcb_correlation_id],
        causation_id:   Thread.current[:tcb_causation_id]
      ).call(within: within, &block)
    end

    def initialize(events_from:, events:, store:, registrations:, correlation_id: nil, causation_id: nil)
      @events_from    = events_from
      @events         = events
      @store          = store
      @registrations  = registrations
      @correlation_id = correlation_id
      @causation_id = causation_id
    end

    def call(within:, &block)
      if within.respond_to?(:transaction)
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
    rescue
      @events_from.each(&:pull_recorded_events)
      raise
    end

    def persist(events)
      return events.map { |event| wrap(event) } unless @store

      persisted = persist_to_store(events)
      remaining = wrap_remaining(events, persisted)

      order_by_original(events, persisted, remaining)
    end

    def persist_to_store(events)
      grouped = Hash.new { |h, k| h[k] = [] }

      events.each do |event|
        registration = @registrations.find { |r| r.event_classes.include?(event.class) }
        next unless registration

        stream_id = StreamId.build(registration.context, event.public_send(registration.stream_id_from_event))
        grouped[stream_id.to_s] << event
      end

      grouped.flat_map do |stream_id, grouped_events|
        @store.append(
          stream_id:      stream_id,
          events:         grouped_events,
          correlation_id: @correlation_id,
          causation_id:   @causation_id
        )
      end
    end

    def wrap_remaining(events, persisted)
      persisted_events = persisted.map(&:event)
      events
        .reject { |event| persisted_events.include?(event) }
        .map    { |event| wrap(event) }
    end

    def order_by_original(events, persisted, remaining)
      all = persisted + remaining
      events.map { |event| all.find { |e| e.event == event } }
    end

    def wrap(event) = TCB::Envelope.wrap(event, correlation_id: @correlation_id, causation_id: @causation_id)
  end
end
