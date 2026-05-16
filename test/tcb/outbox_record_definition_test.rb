# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/active_record_outbox_setup"

module TCB
  class OutboxRecordDefinitionTest < Minitest::Test

    module Invoicing
      include TCB::HandlesEvents

      InvoicePaid = Data.define(:invoice_id)

      persist events(InvoicePaid, stream_id_from_event: :invoice_id)
      on InvoicePaid, ensure_reaction(Class.new { def call(e) = nil })
    end

    def setup
      TCB.reset!
    end

    def teardown
      TCB.reset!
      Invoicing.send(:remove_const, :OutboxRecord) if Invoicing.const_defined?(:OutboxRecord, false)
    end

    def test_outbox_record_defined_for_module_with_ensure_reaction
      TCB.domain_modules = [Invoicing]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      assert Invoicing.const_defined?(:OutboxRecord, false)
    end

    def test_outbox_record_has_correct_table_name
      TCB.domain_modules = [Invoicing]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      assert_equal "tcb__outbox_record_definition_test__invoicing_outbox", Invoicing::OutboxRecord.table_name
    end

    def test_outbox_record_inherits_from_active_record
      TCB.domain_modules = [Invoicing]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      assert Invoicing::OutboxRecord.ancestors.include?(::ActiveRecord::Base)
    end

    def test_outbox_store_set_automatically
      TCB.domain_modules = [Invoicing]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      assert_instance_of TCB::OutboxStore::ActiveRecord, TCB.config.outbox_store
    end

    def test_existing_outbox_record_is_not_overwritten
      sentinel = Class.new
      Invoicing.const_set(:OutboxRecord, sentinel)

      TCB.domain_modules = [Invoicing]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      assert_same sentinel, Invoicing::OutboxRecord
    end

    def test_outbox_record_not_defined_without_ensure_reaction
      mod = Module.new
      mod.instance_variable_set(:@name, "Invoicing")
      def mod.name = @name
      mod.include(TCB::HandlesEvents)
      mod.persist(mod.events(Invoicing::InvoicePaid, stream_id_from_event: :invoice_id))

      TCB.domain_modules = [mod]
      TCB.configure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      refute mod.const_defined?(:OutboxRecord, false)
    end
  end
end
