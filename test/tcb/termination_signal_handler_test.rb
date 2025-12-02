require_relative '../test_helper'

module TCB
  class TerminationSignalHandlerTest < Minitest::Test
    def setup
      @event_bus = Minitest::Mock.new
      @handler = EventBus::TerminationSignalHandler.new(
        event_bus: @event_bus,
        shutdown_timeout: 5.0,
        signals: [:TERM, :INT],
        on_signal: nil
      )
    end

    # Test: Signal handlers are registered during installation
    def test_install_registers_signal_handlers
      trapped_signals = []
      
      # Mock Signal.trap to track what gets registered
      Signal.stub(:trap, ->(sig, &block) { trapped_signals << sig; "DEFAULT" }) do
        @handler.install
      end

      assert_includes trapped_signals, :TERM
      assert_includes trapped_signals, :INT
      assert_equal 2, trapped_signals.size
    end

    # Test: Handle graceful shutdown on first signal
    def test_handle_graceful_shutdown_on_first_signal
      @event_bus.expect(:shutdown, nil, [], drain: true, timeout: 5.0)
      
      # Mock Signal.trap and Process.kill to avoid actual signal operations
      Signal.stub(:trap, ->(*args) { "DEFAULT" }) do
        Process.stub(:kill, ->(*args) { nil }) do
          # Simulate signal handling without actual trap
          @handler.send(:handle_signal, :TERM)
          
          # Give thread time to execute
          sleep 0.15
        end
      end
      
      @event_bus.verify
    end

    # Test: Second signal triggers force shutdown
    def test_second_signal_triggers_force_shutdown
      shutdown_called = false
      force_shutdown_called = false
      
      # Create a real event bus mock that tracks calls
      event_bus = Object.new
      event_bus.define_singleton_method(:shutdown) do |drain:, timeout:|
        shutdown_called = true
        sleep 0.2 # Simulate slow shutdown so second signal arrives during it
      end
      event_bus.define_singleton_method(:force_shutdown) do
        force_shutdown_called = true
      end
      
      handler = EventBus::TerminationSignalHandler.new(
        event_bus: event_bus,
        shutdown_timeout: 5.0,
        signals: [:TERM],
        on_signal: nil
      )
      
      Signal.stub(:trap, ->(*args) { "DEFAULT" }) do
        Process.stub(:kill, ->(*args) { nil }) do
          # First signal starts graceful shutdown
          handler.send(:handle_signal, :TERM)
          sleep 0.05 # Let the shutdown thread start
          
          # Second signal should trigger force shutdown while first is still running
          handler.send(:handle_signal, :TERM)
          sleep 0.05 # Give force shutdown time to execute
        end
      end
      
      assert shutdown_called, "Expected graceful shutdown to be called"
      assert force_shutdown_called, "Expected force shutdown to be called"
    end

    # Test: Custom on_signal callback is invoked
    def test_custom_signal_callback_invoked_before_shutdown
      callback_invoked = false
      received_signal = nil
      
      callback = lambda do |sig|
        callback_invoked = true
        received_signal = sig
      end
      
      handler = EventBus::TerminationSignalHandler.new(
        event_bus: @event_bus,
        shutdown_timeout: 5.0,
        signals: [:TERM],
        on_signal: callback
      )
      
      @event_bus.expect(:shutdown, nil, [], drain: true, timeout: 5.0)
      
      Signal.stub(:trap, ->(*args) { "DEFAULT" }) do
        Process.stub(:kill, ->(*args) { nil }) do
          handler.send(:handle_signal, :TERM)
          sleep 0.15
        end
      end
      
      assert callback_invoked, "Expected on_signal callback to be invoked"
      assert_equal :TERM, received_signal
      @event_bus.verify
    end

    # Test: INT signal triggers shutdown
    def test_int_signal_triggers_shutdown
      @event_bus.expect(:shutdown, nil, [], drain: true, timeout: 5.0)
      
      Signal.stub(:trap, ->(*args) { "DEFAULT" }) do
        Process.stub(:kill, ->(*args) { nil }) do
          @handler.send(:handle_signal, :INT)
          sleep 0.15
        end
      end
      
      @event_bus.verify
    end

    # Test: Shutdown timeout is passed correctly
    def test_shutdown_timeout_passed_to_event_bus
      handler = EventBus::TerminationSignalHandler.new(
        event_bus: @event_bus,
        shutdown_timeout: 10.0,
        signals: [:TERM],
        on_signal: nil
      )
      
      @event_bus.expect(:shutdown, nil, [], drain: true, timeout: 10.0)
      
      Signal.stub(:trap, ->(*args) { "DEFAULT" }) do
        Process.stub(:kill, ->(*args) { nil }) do
          handler.send(:handle_signal, :TERM)
          sleep 0.15
        end
      end
      
      @event_bus.verify
    end

    # Test: Install with actually_trap_signals: false does not trap signals
    def test_install_without_actual_trapping
      trapped_signals = []
      
      Signal.stub(:trap, ->(sig, &block) { trapped_signals << sig; "DEFAULT" }) do
        @handler.install(actually_trap_signals: false)
      end

      assert_empty trapped_signals, "Should not trap signals when actually_trap_signals is false"
    end

    # Test: Multiple signals can be configured
    def test_multiple_signals_configuration
      handler = EventBus::TerminationSignalHandler.new(
        event_bus: @event_bus,
        shutdown_timeout: 5.0,
        signals: [:TERM, :INT, :QUIT],
        on_signal: nil
      )
      
      trapped_signals = []
      
      Signal.stub(:trap, ->(sig, &block) { trapped_signals << sig; "DEFAULT" }) do
        handler.install
      end

      assert_includes trapped_signals, :TERM
      assert_includes trapped_signals, :INT
      assert_includes trapped_signals, :QUIT
      assert_equal 3, trapped_signals.size
    end
  end
end
