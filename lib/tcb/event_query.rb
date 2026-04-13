# frozen_string_literal: true

module TCB
  class EventQuery
    def initialize(store:, context:, stream_id: nil, after_version: nil, occurred_after: nil)
      @store = store
      @context = context
      @stream_id = stream_id
      @after_version = after_version
      @occurred_after = occurred_after
    end

    def stream(aggregate_id)
      self.class.new(
        store: @store,
        context: @context,
        stream_id: StreamId.build(@context, aggregate_id).to_s,
        after_version: @after_version,
        occurred_after: @occurred_after
      )
    end

    def after_version(version)
      self.class.new(
        store: @store,
        context: @context,
        stream_id: @stream_id,
        after_version: version,
        occurred_after: @occurred_after
      )
    end

    def occurred_after(time)
      self.class.new(
        store: @store,
        context: @context,
        stream_id: @stream_id,
        after_version: @after_version,
        occurred_after: time
      )
    end

    def to_a
      return [] unless @stream_id

      @store.read(
        @stream_id,
        after_version: @after_version,
        occurred_after: @occurred_after
      )
    end
  end
end
