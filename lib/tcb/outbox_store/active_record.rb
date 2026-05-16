# frozen_string_literal: true

require "securerandom"

module TCB
  module OutboxStore
    class ActiveRecord
      def initialize(model)
        @model = model
      end

      def insert(event_id:, stream_id:, version:, handler_class:)
        id = SecureRandom.uuid
        now = Time.now

        @model.create!(
          id:            id,
          event_id:      event_id,
          stream_id:     stream_id,
          version:       version,
          handler_class: handler_class.name,
          status:        "pending",
          locked_at:     nil,
          delivered_at:  nil,
          error:         nil,
          created_at:    now
        )

        OutboxEntry.new(
          id:            id,
          event_id:      event_id,
          stream_id:     stream_id,
          version:       version,
          handler_class: handler_class.name,
          status:        :pending,
          locked_at:     nil,
          delivered_at:  nil,
          error:         nil,
          created_at:    now
        )
      end

      def all
        @model.all.map { |r| to_entry(r) }
      end

      def pending
        @model.where(status: "pending").order(:stream_id, :version).map { |r| to_entry(r) }
      end

      def lock(entry, locked_at: Time.now)
        @model.where(id: entry.id).update_all(status: "locked", locked_at: locked_at)
        entry.with(status: :locked, locked_at: locked_at)
      end

      def mark_delivered(entry, delivered_at: Time.now)
        @model.where(id: entry.id).update_all(status: "delivered", delivered_at: delivered_at)
        entry.with(status: :delivered, delivered_at: delivered_at)
      end

      def mark_failed(entry, error:)
        @model.where(id: entry.id).update_all(status: "failed", error: error.message)
        entry.with(status: :failed, error: error.message)
      end

      def recover_stale_locks(older_than:)
        stale = @model.where(status: "locked").where("locked_at < ?", older_than)
        stale.map do |record|
          @model.where(id: record.id).update_all(status: "pending", locked_at: nil)
          to_entry(record).with(status: :pending, locked_at: nil)
        end
      end

      private

      def to_entry(record)
        OutboxEntry.new(
          id:            record.id,
          event_id:      record.event_id,
          stream_id:     record.stream_id,
          version:       record.version,
          handler_class: record.handler_class,
          status:        record.status.to_sym,
          locked_at:     record.locked_at,
          delivered_at:  record.delivered_at,
          error:         record.error,
          created_at:    record.created_at
        )
      end
    end
  end
end
