# frozen_string_literal: true

module TCB
  class SubscriberInvocationFailed < Data.define(
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
    def self.build(handler:, original_event:, error:)
      metadata = SubscriberMetadataExtractor.new(handler).extract

      new(
        original_event: original_event,
        subscriber_type: metadata.subscriber_type,
        subscriber_class: metadata.subscriber_class,
        subscriber_location: metadata.subscriber_location,
        subscriber_source: metadata.subscriber_source,
        error_class: error.class.name,
        error_message: error.message,
        error_backtrace: error.backtrace,
        occurred_at: Time.now
      )
    end
  end
end
