# frozen_string_literal: true

require_relative "../../test_helper"

module TCB
  class OutboxStore::InMemoryTest < Minitest::Test

    class SendInvoice; end
    class NotifyAccounting; end

    def setup
      @store = OutboxStore::InMemory.new
    end

    # insert

    def test_insert_returns_outbox_entry
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_instance_of TCB::OutboxEntry, entry
    end

    def test_insert_assigns_uuid_id
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      refute_nil entry.id
      assert_instance_of String, entry.id
      assert_match(/\A[0-9a-f-]{36}\z/, entry.id)
    end

    def test_insert_stores_event_id
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_equal "evt-1", entry.event_id
    end

    def test_insert_stores_handler_class_as_string
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      assert_equal "TCB::OutboxStore::InMemoryTest::SendInvoice", entry.handler_class
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

    # all

    def test_all_returns_empty_when_no_entries
      assert_equal [], @store.all
    end

    def test_all_returns_all_inserted_entries
      @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.insert(event_id: "evt-2", handler_class: NotifyAccounting, stream_id: "stream-1", version: 1)
      assert_equal 2, @store.all.size
    end

    # pending

    def test_pending_returns_only_pending_entries
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry)
      @store.insert(event_id: "evt-2", handler_class: NotifyAccounting, stream_id: "stream-1", version: 1)

      pending = @store.pending
      assert_equal 1, pending.size
      assert_equal "evt-2", pending.first.event_id
    end

    def test_pending_returns_empty_when_none_pending
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry)
      assert_equal [], @store.pending
    end

    # lock

    def test_lock_returns_new_entry_with_locked_status
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      assert_equal :locked, locked.status
    end

    def test_lock_sets_locked_at
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      assert_instance_of Time, locked.locked_at
    end

    def test_lock_does_not_mutate_original_entry
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry)
      assert_equal :pending, entry.status
      assert_nil entry.locked_at
    end

    def test_lock_updates_stored_entry
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry)
      assert_equal :locked, @store.all.first.status
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

    def test_mark_delivered_updates_stored_entry
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      @store.mark_delivered(locked)
      assert_equal :delivered, @store.all.first.status
    end

    # mark_failed

    def test_mark_failed_returns_entry_with_failed_status
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      error = StandardError.new("something went wrong")
      failed = @store.mark_failed(locked, error: error)
      assert_equal :failed, failed.status
    end

    def test_mark_failed_stores_error_message
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      error = StandardError.new("something went wrong")
      failed = @store.mark_failed(locked, error: error)
      assert_equal "something went wrong", failed.error
    end

    def test_mark_failed_updates_stored_entry
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      locked = @store.lock(entry)
      @store.mark_failed(locked, error: StandardError.new("boom"))
      assert_equal :failed, @store.all.first.status
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

    def test_recover_stale_locks_updates_stored_entries
      entry = @store.insert(event_id: "evt-1", handler_class: SendInvoice, stream_id: "stream-1", version: 1)
      @store.lock(entry, locked_at: Time.now - 600)

      @store.recover_stale_locks(older_than: Time.now - 300)
      assert_equal :pending, @store.all.first.status
      assert_nil @store.all.first.locked_at
    end

    # thread safety

    def test_concurrent_inserts_are_thread_safe
      threads = 10.times.map do |i|
        Thread.new { @store.insert(event_id: "evt-#{i}", handler_class: SendInvoice, stream_id: "stream-1", version: 1) }
      end
      threads.each(&:join)
      assert_equal 10, @store.all.size
    end

    def test_concurrent_inserts_assign_unique_ids
      threads = 10.times.map do |i|
        Thread.new { @store.insert(event_id: "evt-#{i}", handler_class: SendInvoice, stream_id: "stream-1", version: 1) }
      end
      threads.each(&:join)
      ids = @store.all.map(&:id)
      assert_equal 10, ids.uniq.size
    end
  end
end
