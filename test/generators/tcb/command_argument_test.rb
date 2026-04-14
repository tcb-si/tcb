# frozen_string_literal: true

require "test_helper"

$LOAD_PATH.unshift File.expand_path("../../../lib/generators", __dir__)
require "tcb/shared/command_argument"

module TCB
  module Generators
    class CommandArgumentTest < Minitest::Test

      # CommandArgument — data object

      def test_name_and_attrs
        cmd = CommandArgument.new(name: "place_order", attrs: [:order_id, :customer])
        assert_equal "place_order", cmd.name
        assert_equal [:order_id, :customer], cmd.attrs
      end

      def test_command_class_name
        cmd = CommandArgument.new(name: "place_order", attrs: [])
        assert_equal "PlaceOrder", cmd.command_class_name
      end

      def test_handler_class_name
        cmd = CommandArgument.new(name: "place_order", attrs: [])
        assert_equal "PlaceOrderHandler", cmd.handler_class_name
      end

      def test_handler_file_name
        cmd = CommandArgument.new(name: "place_order", attrs: [])
        assert_equal "place_order_handler", cmd.handler_file_name
      end

      def test_handler_file_path
        cmd = CommandArgument.new(name: "place_order", attrs: [])
        assert_equal "app/domain/orders/place_order_handler.rb", cmd.handler_file_path("orders")
      end

      def test_handler_file_path_with_namespaced_module
        cmd = CommandArgument.new(name: "send_welcome_email", attrs: [])
        assert_equal "app/domain/notifications/send_welcome_email_handler.rb", cmd.handler_file_path("notifications")
      end

    end

    class CommandArgumentParserTest < Minitest::Test

      def test_parses_command_with_attributes
        result = CommandArgumentParser.parse(["place_order:order_id,customer"])
        cmd = result.first
        assert_equal "place_order", cmd.name
        assert_equal [:order_id, :customer], cmd.attrs
      end

      def test_parses_command_without_attributes
        result = CommandArgumentParser.parse(["place_order"])
        assert_equal "place_order", result.first.name
        assert_equal [], result.first.attrs
      end

      def test_parses_multiple_commands
        result = CommandArgumentParser.parse(["place_order:order_id,customer", "cancel_order:order_id,reason"])
        assert_equal 2, result.size
        assert_equal "place_order", result.first.name
        assert_equal "cancel_order", result.last.name
      end

      def test_parses_empty_list
        result = CommandArgumentParser.parse([])
        assert_equal [], result
      end

      def test_attrs_are_symbols
        result = CommandArgumentParser.parse(["place_order:order_id,customer"])
        assert_equal [:order_id, :customer], result.first.attrs
      end

      def test_returns_command_argument_instances
        result = CommandArgumentParser.parse(["place_order:order_id"])
        assert_instance_of CommandArgument, result.first
      end

    end
  end
end
