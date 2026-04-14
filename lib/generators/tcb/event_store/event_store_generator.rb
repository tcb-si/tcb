# frozen_string_literal: true

require_relative "../shared/command_argument"

module TCB
  module Generators
    class EventStoreGenerator < Rails::Generators::Base
      namespace "TCB:event_store"
      source_root File.expand_path("templates", __dir__)

      argument :module_name, type: :string
      argument :commands, type: :array, default: [], banner: "command:attr1,attr2"

      class_option :skip_domain,    type: :boolean, default: false, desc: "Skip domain module generation"
      class_option :skip_migration, type: :boolean, default: false, desc: "Skip migration generation"
      class_option :no_comments,    type: :boolean, default: false, desc: "Generate without inline comments"

      def create_domain_module
        return if options[:skip_domain]
        template "domain_module.rb.tt", "app/domain/#{module_name.underscore}.rb"
      end

      def create_handlers
        return if options[:skip_domain]
        parsed_commands.each do |cmd|
          @current_command = cmd
          template "command_handler.rb.tt", cmd.handler_file_path(module_name.underscore)
        end
      end

      def create_migration
        return if options[:skip_migration]
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        template "migration.rb.tt", "db/migrate/#{timestamp}_create_#{table_name}.rb"
      end

      private

      def parsed_commands
        @parsed_commands ||= CommandArgumentParser.parse(commands)
      end

      def module_class_name
        module_name.camelize
      end

      def table_name
        "#{module_name.underscore}_events"
      end

      def migration_class_name
        "Create#{module_name.camelize}Events"
      end

      def comments?
        !options[:no_comments]
      end

      def current_command
        @current_command
      end
    end
  end
end
