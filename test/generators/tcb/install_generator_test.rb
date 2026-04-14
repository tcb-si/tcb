# test/generators/tcb/install_generator_test.rb
require "test_helper"
require "rails/generators/testing/behavior"
require "rails/generators/testing/assertions"
require "generators/tcb/install/install_generator"

module Tcb
  module Generators
    class InstallGeneratorTest < Rails::Generators::TestCase
      tests InstallGenerator
      destination File.expand_path("../../../tmp/generators", __dir__)
      setup :prepare_destination

      def test_creates_initializer
        run_generator
        assert_file "config/initializers/tcb.rb" do |content|
          assert_match "TCB.configure", content
          assert_match "c.event_bus", content
          assert_match "c.event_store", content
          assert_match "c.event_handlers", content
          assert_match "tcb:event_store", content
          assert_match "tcb:domain", content
        end
      end
    end
  end
end
