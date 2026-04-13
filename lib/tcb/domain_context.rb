# frozen_string_literal: true

module TCB
  class DomainContext < Data.define(:value)
    NAMESPACE_SEPARATOR = "/"
    TABLE_SEPARATOR     = "__"
    TABLE_SUFFIX        = "_events"

    def self.from_module(domain_module)
      value = domain_module.name
        .gsub("::", NAMESPACE_SEPARATOR)
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase

      new(value: value)
    end

    def to_s
      value
    end

    def table_name
      value
        .gsub(NAMESPACE_SEPARATOR, TABLE_SEPARATOR)
        .concat(TABLE_SUFFIX)
    end
  end
end
