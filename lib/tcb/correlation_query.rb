# frozen_string_literal: true

module TCB
  class CorrelationQuery
    def initialize(store:, correlation_id:, domains:, occurred_after: nil, occurred_before: nil)
      @store          = store
      @correlation_id = correlation_id
      @domains        = domains
      @occurred_after  = occurred_after
      @occurred_before = occurred_before
    end

    def occurred_after(time)
      self.class.new(store: @store, correlation_id: @correlation_id, domains: @domains, occurred_after: time, occurred_before: @occurred_before)
    end

    def occurred_before(time)
      self.class.new(store: @store, correlation_id: @correlation_id, domains: @domains, occurred_after: @occurred_after, occurred_before: time)
    end

    def between(from, to)
      occurred_after(from).occurred_before(to)
    end

    def to_a
      @domains.flat_map do |domain|
        context = DomainContext.from_module(domain).to_s
        @store.read_by_correlation(@correlation_id, context: context, occurred_after: @occurred_after, occurred_before: @occurred_before)
      end.sort_by(&:occurred_at)
    end
  end
end
