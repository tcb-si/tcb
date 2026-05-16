# frozen_string_literal: true

require_relative "../test_helper"

module TCB
  class RecordOutboxTest < Minitest::Test

    module Invoicing
      include TCB::HandlesEvents

      OrderPlaced = Data.define(:order_id)

      class SendInvoice
        def call(event) = nil
      end

      class NotifyAccounting
        def call(event) = nil
      end

      persist events(OrderPlaced, stream_id_from_event: :order_id)
      on OrderPlaced, ensure_reaction(SendInvoice, NotifyAccounting)
    end

    def setup
      TCB.domain_modules = [Invoicing]
      TCB.configure do |c|
        c.event_bus    = TCB::EventBus.new(sync: true)
        c.event_store  = TCB::EventStore::InMemory.new
        c.outbox_store_class  = TCB::OutboxStore::InMemory
      end
    end

    def outbox_store
      TCB.config.outbox_registrations.first.outbox_store
    end

    def teardown
      TCB.reset!
    end

    def test_record_inserts_outbox_entry_for_each_handler
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      assert_equal 2, outbox_store.all.size
    end

    def test_record_inserts_pending_outbox_entries
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      assert outbox_store.all.all? { |e| e.status == :pending }
    end

    def test_record_sets_correct_handler_class_on_outbox_entry
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      handler_classes = outbox_store.all.map(&:handler_class)
      assert_includes handler_classes, "TCB::RecordOutboxTest::Invoicing::SendInvoice"
      assert_includes handler_classes, "TCB::RecordOutboxTest::Invoicing::NotifyAccounting"
    end

    def test_record_sets_event_id_on_outbox_entry
      envelopes = TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      event_id = envelopes.first.event_id
      assert outbox_store.all.all? { |e| e.event_id == event_id }
    end

    def test_record_does_not_insert_outbox_entries_for_unregistered_events
      TCB.record(events: [Invoicing::OrderPlaced.new(order_id: 1)])

      # only OrderPlaced has ensure_reaction — 2 handlers, 2 entries
      assert_equal 2, outbox_store.all.size
    end

    def test_configure_raises_when_outbox_registrations_present_without_store_class
      TCB.reset!
      TCB.domain_modules = [Invoicing]

      assert_raises(TCB::ConfigurationError) do
        TCB.configure do |c|
          c.event_bus   = TCB::EventBus.new(sync: true)
          c.event_store = TCB::EventStore::InMemory.new
          # no outbox_store_class configured
        end
      end
    end
  end
end
