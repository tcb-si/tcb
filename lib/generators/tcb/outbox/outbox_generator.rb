# frozen_string_literal: true

module TCB
  module Generators
    class OutboxGenerator < Rails::Generators::Base
      namespace "tcb:outbox"
      source_root File.expand_path("templates", __dir__)

      argument :module_name, type: :string

      def create_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        template "migration.rb.tt", "db/migrate/#{timestamp}_create_#{table_name}.rb"
      end

      def create_job
        template "job.rb.tt", "app/jobs/#{job_file_name}.rb"
      end

      private

      def table_name
        "#{module_name.underscore}_outbox"
      end

      def migration_class_name
        "Create#{module_name.camelize}Outbox"
      end

      def module_class_name
        module_name.camelize
      end

      def job_class_name
        "#{module_name.camelize}OutboxJob"
      end

      def job_file_name
        "#{module_name.underscore}_outbox_job"
      end
    end
  end
end
