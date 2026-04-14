# frozen_string_literal: true

require_relative '../../test_helper'

module TCB
  class EventBus::SubscriberRegistryTest < Minitest::Test

    def setup
      @registry = TCB::EventBus::SubscriberRegistry.new
    end

    # add

    def test_add_returns_subscription_token
      handler = proc { |event| }
      subscription = @registry.add(OrderPlaced, handler)

      assert_instance_of TCB::EventBus::SubscriberRegistry::Subscription, subscription
      assert_equal OrderPlaced, subscription.event_class
      assert_equal handler, subscription.handler
    end

    def test_add_makes_handler_available_for_dispatch
      handler = proc { |event| }
      @registry.add(OrderPlaced, handler)

      assert_includes @registry.handlers_for(OrderPlaced), handler
    end

    def test_add_multiple_handlers_for_same_event_class
      handler_a = proc { |event| }
      handler_b = proc { |event| }
      @registry.add(OrderPlaced, handler_a)
      @registry.add(OrderPlaced, handler_b)

      handlers = @registry.handlers_for(OrderPlaced)
      assert_includes handlers, handler_a
      assert_includes handlers, handler_b
    end

    def test_add_handlers_for_different_event_classes
      handler_a = proc { |event| }
      handler_b = proc { |event| }
      @registry.add(OrderPlaced, handler_a)
      @registry.add(UserRegistered, handler_b)

      assert_includes @registry.handlers_for(OrderPlaced), handler_a
      assert_includes @registry.handlers_for(UserRegistered), handler_b
      refute_includes @registry.handlers_for(OrderPlaced), handler_b
    end

    # handlers_for

    def test_handlers_for_returns_empty_when_no_subscriptions
      assert_empty @registry.handlers_for(OrderPlaced)
    end

    def test_handlers_for_returns_frozen_copy
      @registry.add(OrderPlaced, proc { |event| })
      handlers = @registry.handlers_for(OrderPlaced)

      assert_predicate handlers, :frozen?
    end

    # remove

    def test_remove_unregisters_handler
      handler = proc { |event| }
      subscription = @registry.add(OrderPlaced, handler)
      @registry.remove(subscription)

      refute_includes @registry.handlers_for(OrderPlaced), handler
    end

    def test_remove_only_removes_specified_subscription
      handler_a = proc { |event| }
      handler_b = proc { |event| }
      subscription_a = @registry.add(OrderPlaced, handler_a)
      @registry.add(OrderPlaced, handler_b)

      @registry.remove(subscription_a)

      refute_includes @registry.handlers_for(OrderPlaced), handler_a
      assert_includes @registry.handlers_for(OrderPlaced), handler_b
    end

    def test_remove_is_idempotent
      handler = proc { |event| }
      subscription = @registry.add(OrderPlaced, handler)
      @registry.remove(subscription)

      assert_silent { @registry.remove(subscription) }
    end

    # metadata

    def test_add_stores_subscriber_metadata
      handler = proc { |event| }
      subscription = @registry.add(OrderPlaced, handler)
      metadata = @registry.metadata_for(subscription)

      assert_instance_of SubscriberMetadataExtractor::SubscriberMetadata, metadata
      assert_equal :block, metadata.subscriber_type
    end

    def test_remove_cleans_up_metadata
      handler = proc { |event| }
      subscription = @registry.add(OrderPlaced, handler)
      @registry.remove(subscription)

      assert_nil @registry.metadata_for(subscription)
    end

  end
end
