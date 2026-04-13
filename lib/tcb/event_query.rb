# frozen_string_literal: true

module TCB
  class EventQuery
    def initialize(store:, context:, stream_id: nil, from_version: nil, to_version: nil, occurred_after: nil)
      @store = store
      @context = context
      @stream_id = stream_id
      @from_version = from_version
      @to_version = to_version
      @occurred_after = occurred_after
    end

    def stream(aggregate_id)
      self.class.new(
        store: @store,
        context: @context,
        stream_id: StreamId.build(@context, aggregate_id).to_s,
        from_version: @from_version,
        to_version: @to_version,
        occurred_after: @occurred_after
      )
    end

    def from_version(version)
      self.class.new(
        store: @store,
        context: @context,
        stream_id: @stream_id,
        from_version: version,
        to_version: @to_version,
        occurred_after: @occurred_after
      )
    end

    def to_version(version)
      self.class.new(
        store: @store,
        context: @context,
        stream_id: @stream_id,
        from_version: @from_version,
        to_version: version,
        occurred_after: @occurred_after
      )
    end

    def between_versions(from, to)
      from_version(from).to_version(to)
    end

    def occurred_after(time)
      self.class.new(
        store: @store,
        context: @context,
        stream_id: @stream_id,
        from_version: @from_version,
        to_version: @to_version,
        occurred_after: time
      )
    end

    def to_a
      return [] unless @stream_id

      @store.read(
        @stream_id,
        from_version: @from_version,
        to_version: @to_version,
        occurred_after: @occurred_after
      )
    end
  end
end
