require_relative '../test_helper'

module TCB
  class ConfigurationTest < Minitest::Test
    def teardown
      TCB.instance_variable_set(:@config, nil)
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
    ensure
      TCB.config.event_bus.force_shutdown
    end

    def test_mutation_after_configure_raises
      TCB.configure { |c| c.event_bus = TCB::EventBus.new }
      assert_raises(FrozenError) do
        TCB.config.event_bus = TCB::EventBus.new
      end
    ensure
      TCB.config.event_bus.force_shutdown
    end

    def test_configure_twice_raises
      TCB.configure { |c| c.event_bus = TCB::EventBus.new }
      assert_raises(FrozenError) do
        TCB.configure { |c| c.event_bus = TCB::EventBus.new }
      end
    ensure
      TCB.config.event_bus.force_shutdown
    end

    def test_configured_returns_false_when_not_configured
      TCB.instance_variable_set(:@config, nil)
      refute TCB.configured?
    end

    def test_configured_returns_true_when_configured
      TCB.configure { |c| c.event_bus = TCB::EventBus.new }
      assert TCB.configured?
    end
  end
end
