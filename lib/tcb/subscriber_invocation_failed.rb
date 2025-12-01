# frozen_string_literal: true

module TCB
  SubscriberInvocationFailed = Data.define(
    :original_event,
    :subscriber_type,
    :subscriber_class,
    :subscriber_location,
    :subscriber_source,
    :error_class,
    :error_message,
    :error_backtrace,
    :occurred_at
  )
end
