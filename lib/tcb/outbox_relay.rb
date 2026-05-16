# frozen_string_literal: true

module TCB
  class OutboxRelay
    def initialize(outbox_store:, event_store:, lock_timeout:)
      @outbox_store = outbox_store
      @event_store  = event_store
      @lock_timeout = lock_timeout
    end

    def run
      recover_stale_locks
      entries    = lock_pending
      envelopes  = fetch_envelopes(entries)
      entries.each { |entry| process(entry, envelopes[entry.event_id]) }
    end

    private

    def recover_stale_locks
      @outbox_store.recover_stale_locks(older_than: Time.now - @lock_timeout)
    end

    def lock_pending
      @outbox_store
        .pending
        .map { |e| @outbox_store.lock(e) }
    end

    def fetch_envelopes(entries)
      @event_store.read_by_event_ids(entries.map(&:event_id))
    end

    def process(entry, envelope)
      Object.const_get(entry.handler_class).new.call(envelope.event)
      @outbox_store.mark_delivered(entry)
    rescue => error
      @outbox_store.mark_failed(entry, error: error)
    end
  end
end
