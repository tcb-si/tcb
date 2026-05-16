# frozen_string_literal: true

module TCB
  module OutboxStore
    class InMemory
      def initialize(_model = nil)
        @entries = {}
        @mutex = Mutex.new
      end

      def insert(event_id:, stream_id:, version:, handler_class:)
        entry = OutboxEntry.new(
          id:            SecureRandom.uuid,
          event_id:      event_id,
          stream_id:     stream_id,
          version:       version,
          handler_class: handler_class.name,
          status:        :pending,
          locked_at:     nil,
          delivered_at:  nil,
          error:         nil,
          created_at:    Time.now
        )
        @mutex.synchronize { @entries[entry.id] = entry }
        entry
      end

      def all
        @mutex.synchronize { @entries.values.dup }
      end

      def pending
        @mutex
          .synchronize { @entries.values.select { |e| e.status == :pending }
          .sort_by { |e| [e.stream_id, e.version] } }
      end

      def lock(entry, locked_at: Time.now)
        updated = entry.with(status: :locked, locked_at: locked_at)
        @mutex.synchronize { @entries[entry.id] = updated }
        updated
      end

      def mark_delivered(entry, delivered_at: Time.now)
        updated = entry.with(status: :delivered, delivered_at: delivered_at)
        @mutex.synchronize { @entries[entry.id] = updated }
        updated
      end

      def mark_failed(entry, error:)
        updated = entry.with(status: :failed, error: error.message)
        @mutex.synchronize { @entries[entry.id] = updated }
        updated
      end

      def recover_stale_locks(older_than:)
        stale = @mutex.synchronize do
          @entries.values.select { |e| e.status == :locked && e.locked_at < older_than }
        end

        stale.map do |entry|
          updated = entry.with(status: :pending, locked_at: nil)
          @mutex.synchronize { @entries[entry.id] = updated }
          updated
        end
      end
    end
  end
end
