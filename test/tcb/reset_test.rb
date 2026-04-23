# frozen_string_literal: true

require_relative '../test_helper'

module TCB
  class ResetTest < Minitest::Test
    CALLED = []

    module TestDomain
      include TCB::HandlesEvents

      SomethingHappened = Data.define(:id)

      Handler = Class.new do
        define_method(:call) { |event| CALLED << :handled }
      end

      on SomethingHappened, react_with(Handler)
    end

    def setup
      CALLED.clear
      TCB.reset!
      TCB.domain_modules = [TestDomain]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new
        c.event_store = TCB::EventStore::InMemory.new
      end
    end

    def teardown
      TCB.reset!
    end

    # TCB.reset!

    def test_reset_works_on_frozen_config
      assert TCB.config.frozen?
      assert_silent { TCB.reset! }
    end

    def test_reset_clears_event_bus_subscriptions
      TCB.reset!
      TCB.domain_modules = [TestDomain]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new
        c.event_store = TCB::EventStore::InMemory.new
      end
      handlers = TCB.config.event_bus.registry.handlers_for(TestDomain::SomethingHappened)
      assert_equal 1, handlers.size
    end

    def test_reset_calls_event_store_reset_when_supported
      TCB.reset!
      TCB.domain_modules = [TestDomain]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new
        c.event_store = TCB::EventStore::InMemory.new
      end
      assert_equal [], TCB.config.event_store.read("any|stream")
    end

    def test_reset_clears_event_store_data
      TCB.config.event_store.append(stream_id: "orders|1", events: [OrderPlaced.new(order_id: 1, total: 10.0)])
      TCB.reset!
      TCB.domain_modules = [TestDomain]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new
        c.event_store = TCB::EventStore::InMemory.new
      end
      assert_equal [], TCB.config.event_store.read("orders|1")
    end

    def test_reset_skips_event_store_reset_when_not_supported
      store_without_reset = Object.new
      config = TCB::Configuration.new
      config.event_bus = TCB::EventBus.new
      config.event_store = store_without_reset
      config.domain_modules = []
      TCB.instance_variable_set(:@config, config)
      config.freeze

      assert_silent { TCB.reset! }
    end

    # SubscriberRegistry#clear

    def test_registry_clear_removes_all_subscribers
      registry = TCB::EventBus::SubscriberRegistry.new
      registry.add(OrderPlaced, -> (e) {})
      registry.add(OrderPlaced, -> (e) {})
      registry.clear
      assert_empty registry.handlers_for(OrderPlaced)
    end

    # InMemory#reset!

    def test_in_memory_reset_clears_all_streams
      store = TCB::EventStore::InMemory.new
      store.append(stream_id: "orders|1", events: [OrderPlaced.new(order_id: 1, total: 10.0)])
      store.append(stream_id: "orders|2", events: [OrderPlaced.new(order_id: 2, total: 20.0)])
      store.reset!
      assert_equal [], store.read("orders|1")
      assert_equal [], store.read("orders|2")
    end

    def test_in_memory_reset_allows_append_after_reset
      store = TCB::EventStore::InMemory.new
      store.append(stream_id: "orders|1", events: [OrderPlaced.new(order_id: 1, total: 10.0)])
      store.reset!
      store.append(stream_id: "orders|1", events: [OrderPlaced.new(order_id: 1, total: 99.0)])
      envelopes = store.read("orders|1")
      assert_equal 1, envelopes.size
      assert_equal 1, envelopes.first.version
    end

    def test_reset_when_not_configured_is_safe
      TCB.reset!
      assert_silent { TCB.reset! }
    end

    def test_reset_with_graceful_shutdown_time_when_not_configured
      TCB.reset!
      assert_silent { TCB.reset!(graceful_shutdown_time: 5) }
    end
  end
end
