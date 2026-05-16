# frozen_string_literal: true

require_relative "../test_helper"

module TCB
  class OutboxRelayTest < Minitest::Test

    module Invoicing
      include TCB::HandlesEvents

      OrderPlaced = Data.define(:order_id)

      DELIVERED = []

      class SendInvoice
        def call(event)
          Invoicing::DELIVERED << event
        end
      end

      class NotifyAccounting
        def call(event)
          Invoicing::DELIVERED << event
        end
      end

      persist events(OrderPlaced, stream_id_from_event: :order_id)
      on OrderPlaced, ensure_reaction(SendInvoice, NotifyAccounting)
    end

    def setup
      TCB.reset!
      Invoicing::DELIVERED.clear
      @event_store = TCB::EventStore::InMemory.new
      TCB.domain_modules = [Invoicing]
      TCB.configure do |c|
        c.event_bus          = TCB::EventBus.new(sync: true)
        c.event_store        = @event_store
        c.outbox_store_class = TCB::OutboxStore::InMemory
      end
    end

    def outbox_store
      TCB.config.outbox_registrations.first.outbox_store
    end

    def relay
      TCB::OutboxRelay.new(
        outbox_store: outbox_store,
        event_store:  @event_store,
        lock_timeout: 300
      )
    end

    # deliver

    def test_relay_calls_handler_with_envelope
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      relay.run

      assert_equal 2, Invoicing::DELIVERED.size
    end

    def test_relay_passes_event_to_handler
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      relay.run

      assert Invoicing::DELIVERED.all? { |e| e.is_a?(Invoicing::OrderPlaced) }
    end

    def test_relay_marks_entries_as_delivered
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      relay.run

      assert outbox_store.all.all? { |e| e.status == :delivered }
    end

    def test_relay_does_not_process_already_delivered_entries
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])
      relay.run
      relay.run

      assert_equal 2, Invoicing::DELIVERED.size
    end

    # failure

    def test_relay_marks_entry_as_failed_when_handler_raises
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      Invoicing::SendInvoice.define_method(:call) { |e| raise StandardError, "boom" }

      relay.run

      failed = outbox_store.all.select { |e| e.handler_class.end_with?("SendInvoice") }
      assert failed.all? { |e| e.status == :failed }
      assert failed.all? { |e| e.error == "boom" }
    ensure
      Invoicing::SendInvoice.define_method(:call) { |e| Invoicing::DELIVERED << e }
    end

    def test_relay_continues_processing_after_handler_failure
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      Invoicing::SendInvoice.define_method(:call) { |e| raise StandardError, "boom" }

      relay.run

      delivered = outbox_store.all.select { |e| e.handler_class.end_with?("NotifyAccounting") }
      assert delivered.all? { |e| e.status == :delivered }
    ensure
      Invoicing::SendInvoice.define_method(:call) { |e| Invoicing::DELIVERED << e }
    end

    # stale lock recovery

    def test_relay_recovers_stale_locks_before_processing
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      # Simulate stale lock from previous crashed relay
      entry = outbox_store.pending.first
      outbox_store.lock(entry, locked_at: Time.now - 600)

      relay.run

      assert outbox_store.all.all? { |e| e.status == :delivered }
    end

    # ordering

    def test_relay_processes_entries_ordered_by_stream_and_version
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: "b-order")])
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: "a-order")])

      relay.run

      order_ids = Invoicing::DELIVERED.map { |e| e.order_id }
      assert_equal ["a-order", "a-order", "b-order", "b-order"], order_ids
    end
  end
end
