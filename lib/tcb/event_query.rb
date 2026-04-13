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

    def last(count)
      return [] unless @stream_id

      result = @store.read(
        @stream_id,
        from_version: @from_version,
        to_version: @to_version,
        occurred_after: @occurred_after,
        limit: count,
        order: :desc
      )
      result.reverse
    end

    def in_batches(of: 1000, from_version: nil, to_version: nil)
      return enum_for(:in_batches, of: of, from_version: from_version, to_version: to_version) unless block_given?

      cursor = from_version || @from_version
      ceiling = to_version || @to_version

      loop do
        batch = @store.read(
          @stream_id,
          from_version: cursor,
          to_version: ceiling,
          occurred_after: @occurred_after,
          limit: of
        )

        break if batch.empty?

        yield batch

        break if batch.size < of

        cursor = batch.last.version + 1
      end
    end

    def to_a
      result = []
      in_batches { |batch| result.push(*batch) }
      result
    end
  end
end
