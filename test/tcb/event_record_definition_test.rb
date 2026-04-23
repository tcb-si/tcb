# frozen_string_literal: true

require_relative '../test_helper'
require_relative '../support/active_record_setup_no_models'

module TCB
  class EventRecordDefinitionTest < Minitest::Test

    module Invoices
      include TCB::HandlesEvents
      persist events(OrderPlaced, stream_id_from_event: :order_id)
    end

    module WithoutPersist
      include TCB::HandlesEvents
    end

    def setup
      TCB.reset!
      ActiveRecord::Schema.define do
        create_table :invoices_events, force: :cascade do |t|
          t.string   :event_id,    null: false
          t.string   :stream_id,   null: false
          t.integer  :version,     null: false
          t.string   :event_type,  null: false
          t.text     :payload,     null: false
          t.datetime :occurred_at, null: false
        end
        add_index :invoices_events, [:stream_id, :version],
          unique: true, if_not_exists: true

        create_table :payments__charges_events, force: :cascade do |t|
          t.string   :event_id,    null: false
          t.string   :stream_id,   null: false
          t.integer  :version,     null: false
          t.string   :event_type,  null: false
          t.text     :payload,     null: false
          t.datetime :occurred_at, null: false
        end
        add_index :payments__charges_events, [:stream_id, :version],
          unique: true, if_not_exists: true
      end
    end

    def teardown
      TCB.reset!
      Invoices.send(:remove_const, :EventRecord) if Invoices.const_defined?(:EventRecord, false)
    end

    def test_event_record_defined_for_module_with_persist
      TCB.domain_modules = [Invoices]
      TCB.configure_infrastructure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      assert Invoices.const_defined?(:EventRecord, false)
    end

    def test_event_record_has_correct_table_name
      TCB.domain_modules = [Invoices]
      TCB.configure_infrastructure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      assert_equal "tcb__event_record_definition_test__invoices_events", Invoices::EventRecord.table_name
    end

    def test_event_record_inherits_from_active_record
      TCB.domain_modules = [Invoices]
      TCB.configure_infrastructure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      assert Invoices::EventRecord.ancestors.include?(::ActiveRecord::Base)
    end

    def test_existing_event_record_is_not_overwritten
      sentinel = Class.new
      Invoices.const_set(:EventRecord, sentinel)

      TCB.domain_modules = [Invoices]
      TCB.configure_infrastructure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      assert_same sentinel, Invoices::EventRecord
    end

    def test_module_without_persist_does_not_get_event_record
      TCB.domain_modules = [WithoutPersist]
      TCB.configure_infrastructure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      refute WithoutPersist.const_defined?(:EventRecord, false)
    end

    def test_nested_module_uses_double_underscore_convention
      mod = Module.new
      mod.instance_variable_set(:@name, "Payments::Charges")
      def mod.name = @name
      mod.include(TCB::HandlesEvents)
      mod.persist(mod.events(OrderPlaced, stream_id_from_event: :order_id))

      TCB.domain_modules = [mod]
      TCB.configure_infrastructure do |c|
        c.event_bus   = TCB::EventBus.new(sync: true)
        c.event_store = TCB::EventStore::ActiveRecord.new
      end

      klass = mod.const_get(:EventRecord)
      assert_equal "payments__charges_events", klass.table_name
    end
  end
end