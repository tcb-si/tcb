# frozen_string_literal: true

module TCB
  module Generators
    CommandArgument = Data.define(:name, :attrs) do
      def command_class_name
        camelize(name)
      end

      def handler_class_name
        "#{camelize(name)}Handler"
      end

      def handler_file_name
        "#{name}_handler"
      end

      def handler_file_path(module_name)
        "app/domain/#{module_name}/#{handler_file_name}.rb"
      end

      private

      def camelize(str)
        str.split("_").map(&:capitalize).join
      end
    end

    class CommandArgumentParser
      def self.parse(args)
        args.map do |arg|
          name, attrs_str = arg.split(":", 2)
          attrs = attrs_str ? attrs_str.split(",").map(&:to_sym) : []
          CommandArgument.new(name: name, attrs: attrs)
        end
      end
    end
  end
end
