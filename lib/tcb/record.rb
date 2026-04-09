module TCB
  def self.record(aggregates:, within: nil, &block)
    if within
      within.transaction { collect(aggregates, &block) }
    else
      collect(aggregates, &block)
    end
  end

  def self.collect(aggregates, &block)
    block.call
    aggregates.flat_map(&:pull_recorded_events)
  rescue
    aggregates.each(&:pull_recorded_events)
    raise
  end
  private_class_method :collect
end