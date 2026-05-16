# frozen_string_literal: true

require "test_helper"
require "rails/generators/testing/behavior"
require "rails/generators/testing/assertions"
require "generators/tcb/outbox/outbox_generator"

module TCB
  module Generators
    class OutboxGeneratorTest < Rails::Generators::TestCase
      include Rails::Generators::Testing::Assertions

      tests TCB::Generators::OutboxGenerator
      destination File.expand_path("../../../tmp/generators", __dir__)
      setup :prepare_destination

      def test_creates_migration
        run_generator ["invoicing"]
        assert_migration "db/migrate/create_invoicing_outbox.rb"
      end

      def test_migration_creates_table_with_correct_name
        run_generator ["invoicing"]
        assert_migration "db/migrate/create_invoicing_outbox.rb" do |content|
          assert_match(/create_table :invoicing_outbox/, content)
        end
      end

      def test_migration_includes_required_columns
        run_generator ["invoicing"]
        assert_migration "db/migrate/create_invoicing_outbox.rb" do |content|
          assert_match(/t\.string\s+:id/, content)
          assert_match(/t\.string\s+:event_id/, content)
          assert_match(/t\.string\s+:stream_id/, content)
          assert_match(/t\.integer\s+:version/, content)
          assert_match(/t\.string\s+:handler_class/, content)
          assert_match(/t\.string\s+:status/, content)
          assert_match(/t\.datetime\s+:locked_at/, content)
          assert_match(/t\.datetime\s+:delivered_at/, content)
          assert_match(/t\.text\s+:error/, content)
          assert_match(/t\.datetime\s+:created_at/, content)
        end
      end

      def test_migration_includes_indexes
        run_generator ["invoicing"]
        assert_migration "db/migrate/create_invoicing_outbox.rb" do |content|
          assert_match(/add_index :invoicing_outbox, :status/, content)
          assert_match(/add_index :invoicing_outbox, \[:status, :locked_at\]/, content)
          assert_match(/add_index :invoicing_outbox, \[:stream_id, :version\]/, content)
        end
      end

      def test_creates_job
        run_generator ["invoicing"]
        assert_file "app/jobs/invoicing_outbox_job.rb"
      end

      def test_job_content
        run_generator ["invoicing"]
        assert_file "app/jobs/invoicing_outbox_job.rb" do |content|
          assert_match(/class InvoicingOutboxJob < ApplicationJob/, content)
          assert_match(/TCB::OutboxRelay\.new/, content)
          assert_match(/Invoicing::OutboxRecord/, content)
          assert_match(/TCB\.config\.event_store/, content)
        end
      end
    end
  end
end
