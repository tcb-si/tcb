# frozen_string_literal: true

module TCB
  class EventBus
    class QueuePressureMonitor
      def self.for(max_queue_size:, high_water_mark:)
        return new(high_water_mark:) if max_queue_size && high_water_mark

        NullQueuePressureMonitor.new
      end

      def initialize(high_water_mark:)
        @high_water_mark = high_water_mark
        @emitted = false
      end

      def check?(queue_size)
        if queue_size >= @high_water_mark
          return false if @emitted
          @emitted = true
          true
        else
          @emitted = false
          false
        end
      end
    end

    class NullQueuePressureMonitor
      def check?(_queue_size)
        false
      end
    end
  end
end