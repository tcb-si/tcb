# frozen_string_literal: true

module TCB
  class SubscriberMetadataExtractor
    SubscriberMetadata = Data.define(
      :subscriber_type,
      :subscriber_class,
      :subscriber_location,
      :subscriber_source
    )

    def initialize(handler)
      @handler = handler
    end

    def extract
      if @handler.is_a?(Proc)
        extract_proc_metadata
      else
        extract_class_metadata
      end
    end

    private

    def extract_proc_metadata
      file, line = @handler.source_location
      location = file ? "#{file}:#{line}" : nil

      SubscriberMetadata.new(
        subscriber_type: :block,
        subscriber_class: "Proc",
        subscriber_location: location,
        subscriber_source: extract_source(@handler)
      )
    end

    def extract_class_metadata
      file, line = @handler.class.source_location
      location = file ? "#{file}:#{line}" : nil

      SubscriberMetadata.new(
        subscriber_type: :class,
        subscriber_class: @handler.class.name,
        subscriber_location: location,
        subscriber_source: extract_method_source(@handler, :call)
      )
    end

    def extract_source(proc_or_method)
      return nil unless defined?(MethodSource) # TODO/TBD: We'd need to extract the source of the block

      proc_or_method.source
    rescue MethodSource::SourceNotFoundError, LoadError
      nil
    end

    def extract_method_source(handler_instance, method_name)
      return nil unless defined?(MethodSource)

      handler_instance.method(method_name).source
    rescue MethodSource::SourceNotFoundError, LoadError, NameError
      nil
    end
  end
end
