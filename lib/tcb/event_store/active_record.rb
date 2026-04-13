# frozen_string_literal: true

require "securerandom"

module TCB
  class EventStore
    class ActiveRecord
      def initialize
        @mutex = Mutex.new
      end

      def append(stream_id:, events:, occurred_at: Time.now)
        @mutex.synchronize do
          next_ver = next_version(stream_id)

          envelopes = events.map.with_index(next_ver) do |event, version|
            event_id = SecureRandom.uuid

            event_record_for(stream_id).create!(
              event_id:    event_id,
              stream_id:   stream_id,
              version:     version,
              event_type:  event.class.name,
              payload:     serialize(event),
              occurred_at: occurred_at
            )

            EventStreamEnvelope.new(
              event:       event,
              event_id:    event_id,
              stream_id:   stream_id,
              version:     version,
              occurred_at: occurred_at
            )
          end

          envelopes
        end
      end

      def read(stream_id, after_version: nil, occurred_after: nil)
        scope = event_record_for(stream_id)
          .where(stream_id: stream_id)
          .order(:version)

        scope = scope.where("version > ?", after_version)   if after_version
        scope = scope.where("occurred_at > ?", occurred_after) if occurred_after

        scope.map do |record|
          EventStreamEnvelope.new(
            event:       deserialize(record.payload),
            event_id:    record.event_id,
            stream_id:   record.stream_id,
            version:     record.version,
            occurred_at: record.occurred_at
          )
        end
      end

      private

      def next_version(stream_id)
        event_record_for(stream_id)
          .where(stream_id: stream_id)
          .maximum(:version)
          .to_i + 1
      end

      def event_record_for(stream_id)
        context = stream_id.split("|").first
        module_name = context
          .split("/")
          .map { |part| part.split("_").map(&:capitalize).join }
          .join("::")

        Object.const_get("#{module_name}::EventRecord")
      end

      def serialize(event)
        YAML.dump(event)
      end

      def deserialize(payload)
        YAML.safe_load(payload, permitted_classes: permitted_classes, aliases: true)
      end

      def permitted_classes
        TCB.config.permitted_serialization_classes
      end
    end
  end
end
