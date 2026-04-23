require_relative '../test_helper'

module TCB
  class ConfigurationTest < Minitest::Test
    def teardown
      TCB.reset!
    end

    module SomeModule
    end

    def test_domain_modules_stores_modules_without_configuring
      TCB.domain_modules = [SomeModule]
      assert_equal [SomeModule], TCB.domain_modules
      refute TCB.configured?  # bus še ni konfiguriran
    end

    def test_configure_sets_event_bus
      bus = TCB::EventBus.new(sync: true)
      TCB.configure do |c|
        c.event_bus   = bus
        c.event_store = TCB::EventStore::InMemory.new
      end
      assert_equal bus, TCB.config.event_bus
    end

    def test_configure_sets_event_store
      store = TCB::EventStore::InMemory.new
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = store
      end
      assert_equal store, TCB.config.event_store
    end

    def test_configure_freezes_config
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::InMemory.new
      end
      assert TCB.config.frozen?
    end

    def test_configure_without_domain_modules_is_safe
      assert_silent do
        TCB.configure do |c|
          c.event_bus   = TCB::EventBus.new(sync: true)
          c.event_store = TCB::EventStore::InMemory.new
        end
      end
    end

    def test_configure_flushes_domain_module_subscriptions
      called = []
      mod = Module.new do
        include TCB::HandlesEvents
        event_class = Class.new
        const_set(:SomeEvent, event_class)
        handler = Class.new { define_method(:call) { |e| called << :handled } }
        on event_class, react_with(handler)
      end

      TCB.domain_modules = [mod]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::InMemory.new
      end

      TCB.publish(mod::SomeEvent.new)
      assert_includes called, :handled
    end

    def test_event_bus_raises_if_not_configured
      assert_raises(TCB::ConfigurationError) do
        TCB.config.event_bus
      end
    end

    def test_configure_sets_event_bus
      bus = TCB::EventBus.new
      TCB.configure { |c| c.event_bus = bus }
      assert_equal bus, TCB.config.event_bus
    ensure
      bus.force_shutdown
    end

    def test_config_is_frozen_after_configure
      TCB.configure { |c| c.event_bus = TCB::EventBus.new }
      assert TCB.config.frozen?
    end

    def test_mutation_after_configure_raises
      TCB.configure { |c| c.event_bus = TCB::EventBus.new }
      assert_raises(FrozenError) do
        TCB.config.event_bus = TCB::EventBus.new
      end
    end

    def test_configure_twice_raises
      TCB.configure { |c| c.event_bus = TCB::EventBus.new }
      assert_raises(FrozenError) do
        TCB.configure { |c| c.event_bus = TCB::EventBus.new }
      end
    end

    def test_configured_returns_false_when_not_configured
      TCB.instance_variable_set(:@config, nil)
      refute TCB.configured?
    end

    def test_configured_returns_true_when_configured
      TCB.configure { |c| c.event_bus = TCB::EventBus.new }
      assert TCB.configured?
    end

    def test_configured_returns_false_when_config_exists_but_event_bus_not_set
      TCB.instance_variable_set(:@config, TCB::Configuration.new)
      refute TCB.configured?
    end
  end
end
