# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/active_record_outbox_setup"

module TCB
  class OutboxStore::ActiveRecordTest < Minitest::Test

    class SendInvoice; end
    class NotifyAccounting; end

    def setup
      ::Invoicing::OutboxRecord.delete_all
      @store = OutboxStore::ActiveRecord.new(::Invoicing::OutboxRecord)
    end

    def teardown
      ::Invoicing::OutboxRecord.delete_all
    end

    # insert

    def test_insert_returns_outbox_entry
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_instance_of TCB::OutboxEntry, entry
    end

    def test_insert_assigns_uuid_id
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_match(/\A[0-9a-f-]{36}\z/, entry.id)
    end

    def test_insert_stores_event_id
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_equal "evt-1", entry.event_id
    end

    def test_insert_stores_handler_class_as_string
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_equal "TCB::OutboxStore::ActiveRecordTest::SendInvoice", entry.handler_class
    end

    def test_insert_sets_status_to_pending
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_equal :pending, entry.status
    end

    def test_insert_sets_created_at
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_instance_of Time, entry.created_at
    end

    def test_insert_sets_nil_for_optional_fields
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_nil entry.locked_at
      assert_nil entry.delivered_at
      assert_nil entry.error
    end

    def test_insert_assigns_unique_ids
      e1 = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      e2 = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      refute_equal e1.id, e2.id
    end

    def test_insert_persists_to_database
      @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_equal 1, Invoicing::OutboxRecord.count
    end

    # all

    def test_all_returns_empty_when_no_entries
      assert_equal [], @store.all
    end

    def test_all_returns_all_inserted_entries
      @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.insert(event_id: "evt-2", handler_class: NotifyAccounting, stream_id: "stream-1", version: 2)
      assert_equal 2, @store.all.size
    end

    def test_all_returns_outbox_entries
      @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_instance_of TCB::OutboxEntry, @store.all.first
    end

    # pending

    def test_pending_returns_only_pending_entries
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry)
      @store.insert(event_id: "evt-2", handler_class: NotifyAccounting, stream_id: "stream-1", version: 2)

      pending = @store.pending
      assert_equal 1, pending.size
      assert_equal "evt-2", pending.first.event_id
    end

    def test_pending_returns_empty_when_none_pending
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry)
      assert_equal [], @store.pending
    end

    def test_pending_ordered_by_stream_id_and_version
      @store.insert(event_id: "evt-2", handler_class: SendInvoice, stream_id: "stream-1", version: 2)
      @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)

      pending = @store.pending
      assert_equal [1, 2], pending.map(&:version)
    end

    # lock

    def test_lock_returns_entry_with_locked_status
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      assert_equal :locked, locked.status
    end

    def test_lock_sets_locked_at
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      assert_instance_of Time, locked.locked_at
    end

    def test_lock_persists_to_database
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry)
      assert_equal "locked", Invoicing::OutboxRecord.first.status
    end

    # mark_delivered

    def test_mark_delivered_returns_entry_with_delivered_status
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      delivered = @store.mark_delivered(locked)
      assert_equal :delivered, delivered.status
    end

    def test_mark_delivered_sets_delivered_at
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      delivered = @store.mark_delivered(locked)
      assert_instance_of Time, delivered.delivered_at
    end

    def test_mark_delivered_persists_to_database
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      @store.mark_delivered(locked)
      assert_equal "delivered", Invoicing::OutboxRecord.first.status
    end

    # mark_failed

    def test_mark_failed_returns_entry_with_failed_status
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      failed = @store.mark_failed(locked, error: StandardError.new("boom"))
      assert_equal :failed, failed.status
    end

    def test_mark_failed_stores_error_message
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      failed = @store.mark_failed(locked, error: StandardError.new("something went wrong"))
      assert_equal "something went wrong", failed.error
    end

    def test_mark_failed_persists_to_database
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      @store.mark_failed(locked, error: StandardError.new("boom"))
      assert_equal "failed", Invoicing::OutboxRecord.first.status
    end

    # recover_stale_locks

    def test_recover_stale_locks_returns_stale_entries_as_pending
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry, locked_at: Time.now - 600)

      recovered = @store.recover_stale_locks(older_than: Time.now - 300)
      assert_equal 1, recovered.size
      assert_equal :pending, recovered.first.status
      assert_nil recovered.first.locked_at
    end

    def test_recover_stale_locks_does_not_recover_fresh_locks
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry)

      recovered = @store.recover_stale_locks(older_than: Time.now - 300)
      assert_equal [], recovered
    end

    def test_recover_stale_locks_persists_to_database
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry, locked_at: Time.now - 600)

      @store.recover_stale_locks(older_than: Time.now - 300)
      assert_equal "pending", Invoicing::OutboxRecord.first.status
      assert_nil Invoicing::OutboxRecord.first.locked_at
    end
  end
end
