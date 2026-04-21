# frozen_string_literal: true

require_relative '../test_helper'

module TCB
  class ResetTest < Minitest::Test
    include MinitestHelpers

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
      TCB.instance_variable_set(:@config, nil)
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new
        c.event_store = TCB::EventStore::InMemory.new
        c.domain_modules = [TestDomain]
      end
    end

    def teardown
      TCB.config.event_bus.force_shutdown rescue nil  # ← rescue nil
      TCB.instance_variable_set(:@config, nil)
    end

    # TCB.reset!

    def test_reset_clears_event_bus_subscriptions
      TCB.reset!
      handlers = TCB.config.event_bus.registry.handlers_for(TestDomain::SomethingHappened)
      assert_equal 1, handlers.size
    end

    def test_reset_re_registers_handlers_from_config
      TCB.reset!
      TCB.publish(TestDomain::SomethingHappened.new(id: 1))
      poll_assert("handler called after reset") { CALLED.include?(:handled) }
    end

    def test_reset_does_not_duplicate_subscriptions
      TCB.reset!
      TCB.reset!
      handlers = TCB.config.event_bus.registry.handlers_for(TestDomain::SomethingHappened)
      assert_equal 1, handlers.size
    end

    def test_reset_works_on_frozen_config
      assert TCB.config.frozen?
      assert_silent { TCB.reset! }
    end

    def test_reset_calls_event_store_reset_when_supported
      TCB.reset!
      assert_equal [], TCB.config.event_store.read("any|stream")
    end

    def test_reset_clears_event_store_data
      TCB.config.event_store.append(stream_id: "orders|1", events: [OrderPlaced.new(order_id: 1, total: 10.0)])
      TCB.reset!
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

    def test_reset_reconfigures_from_original_block
      # po reset! je config svež, ne frozen
      TCB.reset!
      assert TCB.config.frozen?  # še ni konfiguriran — ali...
    end

    def test_reset_creates_fresh_event_bus
      original_bus = TCB.config.event_bus
      TCB.reset!
      refute_same original_bus, TCB.config.event_bus
    end

    def test_reset_without_configure_block_clears_config
      TCB.instance_variable_set(:@configure_block, nil)
      TCB.reset!
      assert_raises(TCB::ConfigurationError) { TCB.config.event_bus }
    end

    def test_reset_with_graceful_shutdown_time_force_shuts_down_bus
      original_bus = TCB.config.event_bus
      TCB.reset!(graceful_shutdown_time: 0.1)
      refute_same original_bus, TCB.config.event_bus
    end

    def test_reset_with_graceful_shutdown_time_when_not_configured
      TCB.instance_variable_set(:@configure_block, nil)
      TCB.instance_variable_set(:@config, nil)
      assert_silent { TCB.reset!(graceful_shutdown_time: 5) }
    end
  end
end
