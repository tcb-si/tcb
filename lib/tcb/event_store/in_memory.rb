# frozen_string_literal: true

require "securerandom"

module TCB
  class EventStore
    class InMemory
      def initialize
        @streams = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
      end

      def append(stream_id:, events:, occurred_at: Time.now, correlation_id: nil, causation_id: nil)
        @mutex.synchronize do
          envelopes = events.map.with_index(next_version(stream_id)) do |event, version|
            Envelope.new(
              event:          event,
              event_id:       SecureRandom.uuid,
              stream_id:      stream_id,
              version:        version,
              occurred_at:    occurred_at,
              correlation_id: correlation_id,
              causation_id:   causation_id
            )
          end
          @streams[stream_id].concat(envelopes)
          envelopes
        end
      end

      def read(stream_id, from_version: nil, to_version: nil, occurred_after: nil, limit: nil, order: :asc)
        @mutex.synchronize { @streams[stream_id].dup }
          .then { |e| from_version   ? e.select { |env| env.version >= from_version }      : e }
          .then { |e| to_version     ? e.select { |env| env.version <= to_version }        : e }
          .then { |e| occurred_after ? e.select { |env| env.occurred_at > occurred_after } : e }
          .then { |e| order == :desc ? e.reverse                                           : e }
          .then { |e| limit          ? e.first(limit)                                      : e }
      end

      def reset!
        @mutex.synchronize do
          @streams = Hash.new { |h, k| h[k] = [] }
        end
      end

      private

      def next_version(stream_id)
        @streams[stream_id].size + 1
      end
    end
  end
end