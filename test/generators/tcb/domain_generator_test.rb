# frozen_string_literal: true

require "test_helper"
require "rails/generators/testing/behavior"
require "rails/generators/testing/assertions"

$LOAD_PATH.unshift File.expand_path("lib/generators", Dir.pwd)
require "tcb/shared/command_argument"
require "tcb/domain/domain_generator"

module TCB
  module Generators
    class DomainGeneratorTest < Rails::Generators::TestCase
      tests TCB::Generators::DomainGenerator
      destination File.expand_path("tmp/generators", Dir.pwd)
      setup :prepare_destination

      # Domain module

      def test_creates_domain_module
        run_generator ["notifications"]
        assert_file "app/domain/notifications.rb" do |content|
          assert_match "module Notifications", content
          assert_match "include TCB::HandlesEvents", content
        end
      end

      def test_domain_module_contains_events_block
        run_generator ["notifications"]
        assert_file "app/domain/notifications.rb" do |content|
          assert_match "# Events", content
        end
      end

      def test_domain_module_contains_reactions_block
        run_generator ["notifications"]
        assert_file "app/domain/notifications.rb" do |content|
          assert_match "# Reactions", content
        end
      end

      def test_domain_module_does_not_contain_persistence_block
        run_generator ["notifications"]
        assert_file "app/domain/notifications.rb" do |content|
          assert_no_match(/persist events/, content)
          assert_no_match(/stream_id_from/, content)
        end
      end

      def test_domain_module_generates_commands_from_args
        run_generator ["notifications", "send_welcome_email:user_id,email"]
        assert_file "app/domain/notifications.rb" do |content|
          assert_match "SendWelcomeEmail = Data.define(:user_id, :email)", content
          assert_match "def validate!", content
          assert_match "user_id is required", content
          assert_match "email is required", content
        end
      end

      def test_domain_module_generates_facade_with_publish
        run_generator ["notifications", "send_welcome_email:user_id,email"]
        assert_file "app/domain/notifications.rb" do |content|
          assert_match "def self.send_welcome_email(user_id:, email:)", content
          assert_match "TCB.publish(SendWelcomeEmail.new(user_id: user_id, email: email))", content
        end
      end

      def test_domain_module_generates_multiple_commands
        run_generator ["notifications", "send_welcome_email:user_id,email", "send_verification_sms:user_id,phone"]
        assert_file "app/domain/notifications.rb" do |content|
          assert_match "SendWelcomeEmail = Data.define(:user_id, :email)", content
          assert_match "SendVerificationSms = Data.define(:user_id, :phone)", content
          assert_match "def self.send_welcome_email", content
          assert_match "def self.send_verification_sms", content
        end
      end

      def test_skip_domain_flag
        run_generator ["notifications", "--skip-domain"]
        assert_no_file "app/domain/notifications.rb"
      end

      # Command handlers

      def test_creates_handler_for_each_command
        run_generator ["notifications", "send_welcome_email:user_id,email", "send_verification_sms:user_id,phone"]
        assert_file "app/domain/notifications/send_welcome_email_handler.rb" do |content|
          assert_match "module Notifications", content
          assert_match "class SendWelcomeEmailHandler", content
          assert_match "def call(command)", content
        end
        assert_file "app/domain/notifications/send_verification_sms_handler.rb" do |content|
          assert_match "class SendVerificationSmsHandler", content
        end
      end

      def test_handler_contains_publish_comment
        run_generator ["notifications", "send_welcome_email:user_id,email"]
        assert_file "app/domain/notifications/send_welcome_email_handler.rb" do |content|
          assert_match "TCB.publish", content
        end
      end

      def test_handler_does_not_contain_record_comment
        run_generator ["notifications", "send_welcome_email:user_id,email"]
        assert_file "app/domain/notifications/send_welcome_email_handler.rb" do |content|
          assert_no_match(/TCB\.record/, content)
        end
      end

      def test_no_handlers_without_commands
        run_generator ["notifications"]
        assert_no_file "app/domain/notifications/send_welcome_email_handler.rb"
      end

      # No migration

      def test_does_not_create_migration
        run_generator ["notifications"]
        migration_files = Dir[File.join(destination_root, "db/migrate/*.rb")]
        assert_empty migration_files, "Expected no migration file to be created"
      end

      # --no-comments flag

      def test_no_comments_flag_removes_comments
        run_generator ["notifications", "send_welcome_email:user_id,email", "--no-comments"]
        assert_file "app/domain/notifications.rb" do |content|
          assert_no_match(/# Events/, content)
          assert_no_match(/# Reactions/, content)
        end
      end
    end
  end
end
