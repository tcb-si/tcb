# frozen_string_literal: true

module PollAssert
  def poll_assert(message = nil, within: 1.0, interval: 0.01, &block)
    deadline = Time.now + within

    loop do
      return if block.call

      if Time.now >= deadline
        failure_message = "Condition not met within #{within}s"
        failure_message += ": \"#{message}\"" if message
        raise Minitest::Assertion, failure_message
      end

      sleep interval
    end
  end
end
