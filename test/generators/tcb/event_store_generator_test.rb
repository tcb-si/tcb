# frozen_string_literal: true

require "test_helper"
require "rails/generators/testing/behavior"
require "rails/generators/testing/assertions"

$LOAD_PATH.unshift File.expand_path("../../../lib/generators", __dir__)
require "tcb/shared/command_argument"
require "tcb/event_store/event_store_generator"

module TCB
  module Generators
    class EventStoreGeneratorTest < Rails::Generators::TestCase
      tests EventStoreGenerator
      destination File.expand_path("../../../tmp/generators", __dir__)
      setup :prepare_destination

      # Domain module

      def test_creates_domain_module
        run_generator ["orders"]
        assert_file "app/domain/orders.rb" do |content|
          assert_match "module Orders", content
          assert_match "include TCB::HandlesEvents", content
        end
      end

      def test_domain_module_contains_events_block
        run_generator ["orders"]
        assert_file "app/domain/orders.rb" do |content|
          assert_match "# Events", content
        end
      end

      def test_domain_module_contains_persistence_block
        run_generator ["orders"]
        assert_file "app/domain/orders.rb" do |content|
          assert_match "# Persistence", content
          assert_match "stream_id_from_event:", content
        end
      end

      def test_domain_module_contains_reactions_block
        run_generator ["orders"]
        assert_file "app/domain/orders.rb" do |content|
          assert_match "# Reactions", content
        end
      end

      def test_domain_module_generates_commands_from_args
        run_generator ["orders", "place_order:order_id,customer"]
        assert_file "app/domain/orders.rb" do |content|
          assert_match "PlaceOrder = Data.define(:order_id, :customer)", content
          assert_match "def validate!", content
          assert_match "order_id is required", content
          assert_match "customer is required", content
        end
      end

      def test_domain_module_generates_facade_methods
        run_generator ["orders", "place_order:order_id,customer"]
        assert_file "app/domain/orders.rb" do |content|
          assert_match "def self.place_order(order_id:, customer:)", content
          assert_match "TCB.dispatch(PlaceOrder.new(order_id: order_id, customer: customer))", content
        end
      end

      def test_domain_module_generates_multiple_commands
        run_generator ["orders", "place_order:order_id,customer", "cancel_order:order_id,reason"]
        assert_file "app/domain/orders.rb" do |content|
          assert_match "PlaceOrder = Data.define(:order_id, :customer)", content
          assert_match "CancelOrder = Data.define(:order_id, :reason)", content
          assert_match "def self.place_order", content
          assert_match "def self.cancel_order", content
        end
      end

      def test_domain_module_skipped_if_exists
        run_generator ["orders"]
        run_generator ["orders"]
        # Rails generator framework handles skip — no error raised
      end

      def test_skip_domain_flag
        run_generator ["orders", "--skip-domain"]
        assert_no_file "app/domain/orders.rb"
      end

      # Command handlers

      def test_creates_handler_for_each_command
        run_generator ["orders", "place_order:order_id,customer", "cancel_order:order_id,reason"]
        assert_file "app/domain/orders/place_order_handler.rb" do |content|
          assert_match "module Orders", content
          assert_match "class PlaceOrderHandler", content
          assert_match "def call(command)", content
        end
        assert_file "app/domain/orders/cancel_order_handler.rb" do |content|
          assert_match "class CancelOrderHandler", content
        end
      end

      def test_handler_contains_record_publish_comments
        run_generator ["orders", "place_order:order_id,customer"]
        assert_file "app/domain/orders/place_order_handler.rb" do |content|
          assert_match "TCB.record", content
          assert_match "TCB.publish", content
        end
      end

      def test_no_handlers_without_commands
        run_generator ["orders"]
        assert_no_file "app/domain/orders/place_order_handler.rb"
      end

      # Migration

      def test_creates_migration
        run_generator ["orders"]
        migration_file = Dir[File.join(destination_root, "db/migrate/*_create_orders_events.rb")].first
        assert migration_file, "Expected migration file to be created"
        assert_file migration_file.sub(destination_root + "/", "") do |content|
          assert_match "create_table :orders_events", content
          assert_match "t.string   :event_id", content
          assert_match "t.string   :stream_id", content
          assert_match "t.integer  :version", content
          assert_match "t.string   :event_type", content
          assert_match "t.text     :payload", content
          assert_match "t.datetime :occurred_at", content
          assert_match "add_index :orders_events, [:stream_id, :version], unique: true", content
        end
      end

      def test_skip_migration_flag
        run_generator ["orders", "--skip-migration"]
        migration_files = Dir[File.join(destination_root, "db/migrate/*_create_orders_events.rb")]
        assert_empty migration_files, "Expected no migration file to be created"
      end

      # --no-comments flag

      def test_no_comments_flag_removes_comments
        run_generator ["orders", "place_order:order_id,customer", "--no-comments"]
        assert_file "app/domain/orders.rb" do |content|
          assert_no_match(/# Events/, content)
          assert_no_match(/# Persistence/, content)
          assert_no_match(/# Reactions/, content)
        end
      end
    end
  end
end
