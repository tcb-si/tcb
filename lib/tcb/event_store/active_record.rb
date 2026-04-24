# frozen_string_literal: true

require "securerandom"

module TCB
  class EventStore
    class ActiveRecord
      def initialize
        @mutex = Mutex.new
      end

      def append(stream_id:, events:, occurred_at: Time.now, correlation_id: nil, causation_id: nil)
        @mutex.synchronize do
          next_ver = next_version(stream_id)

          envelopes = events.map.with_index(next_ver) do |event, version|
            event_id = SecureRandom.uuid

            event_record_for(stream_id).create!(
              event_id:       event_id,
              stream_id:      stream_id,
              version:        version,
              event_type:     event.class.name,
              payload:        serialize(event),
              occurred_at:    occurred_at,
              correlation_id: correlation_id,
              causation_id:   causation_id
            )

            TCB::Envelope.new(
              event:          event,
              event_id:       event_id,
              stream_id:      stream_id,
              version:        version,
              occurred_at:    occurred_at,
              correlation_id: correlation_id,
              causation_id:   causation_id
            )
          end

          envelopes
        end
      end

      def read(stream_id, from_version: nil, to_version: nil, occurred_after: nil, limit: nil, order: :asc)
        scope = event_record_for(stream_id)
          .where(stream_id: stream_id)
          .order(version: order)

        scope = scope.where("version >= ?", from_version) if from_version
        scope = scope.where("version <= ?", to_version) if to_version
        scope = scope.where("occurred_at > ?", occurred_after) if occurred_after
        scope = scope.limit(limit) if limit

        scope.map do |record|
          TCB::Envelope.new(
            event:          deserialize(record.payload),
            event_id:       record.event_id,
            stream_id:      record.stream_id,
            version:        record.version,
            occurred_at:    record.occurred_at,
            correlation_id: record.correlation_id,
            causation_id:   record.causation_id
          )
        end
      end

      def read_by_correlation(correlation_id, context:, occurred_after: nil, occurred_before: nil)
        tables = find_tables_for_context(context)
        return [] if tables.empty?

        union_sql = tables.map do |table|
          conditions = ["correlation_id = ?"]
          conditions << "occurred_at > ?" if occurred_after
          conditions << "occurred_at < ?" if occurred_before

          "SELECT * FROM #{table} WHERE #{conditions.join(' AND ')}"
        end.join(" UNION ALL ")

        bindings = tables.flat_map do
          params = [correlation_id]
          params << occurred_after  if occurred_after
          params << occurred_before if occurred_before
          params
        end

        sql = "#{union_sql} ORDER BY occurred_at ASC"
        records = ::ActiveRecord::Base.connection.exec_query(
          ::ActiveRecord::Base.sanitize_sql_array([sql, *bindings])
        )

        records.map do |record|
          TCB::Envelope.new(
            event:          deserialize(record["payload"]),
            event_id:       record["event_id"],
            stream_id:      record["stream_id"],
            version:        record["version"],
            occurred_at:    Time.parse(record["occurred_at"].to_s),
            correlation_id: record["correlation_id"],
            causation_id:   record["causation_id"]
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

      def find_tables_for_context(context)
        ::ActiveRecord::Base.connection.tables.select do |table|
          table.start_with?(context.gsub("/", "__").gsub("::", "__")) &&
            table.end_with?("_events")
        end
      end
    end
  end
end
