# frozen_string_literal: true

module TCB
  EventBusQueuePressure = Data.define(
    :queue_size,      # current number of elements in queue
    :max_queue_size,  # maximum queue capacity
    :occupancy,       # queue_size / max_queue_size (float)
    :occurred_at      # timestamp
  )
end
