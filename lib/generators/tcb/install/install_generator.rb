# frozen_string_literal: true

module TCB
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a TCB initializer in config/initializers"

      def create_initializer
        template "tcb.rb.tt", "config/initializers/tcb.rb"
      end
    end
  end
end
