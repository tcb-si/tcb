# frozen_string_literal: true

require_relative '../test_helper'

module TCB
  class DomainContextTest < Minitest::Test

    module Orders
    end

    module Payments
      module Charges
      end
    end

    def test_from_module_simple_module
      context = DomainContext.from_module(Orders)
      assert_equal "tcb/domain_context_test/orders", context.to_s
    end

    def test_from_module_nested_module
      context = DomainContext.from_module(Payments::Charges)
      assert_equal "tcb/domain_context_test/payments/charges", context.to_s
    end

    def test_table_name_simple_module
      context = DomainContext.from_module(Orders)
      assert_equal "tcb__domain_context_test__orders_events", context.table_name
    end

    def test_table_name_nested_module
      context = DomainContext.from_module(Payments::Charges)
      assert_equal "tcb__domain_context_test__payments__charges_events", context.table_name
    end

    def test_equality
      assert_equal DomainContext.from_module(Orders), DomainContext.from_module(Orders)
    end

    def test_inequality
      refute_equal DomainContext.from_module(Orders), DomainContext.from_module(Payments::Charges)
    end

    def test_namespace_separator_constant
      assert_equal "/", DomainContext::NAMESPACE_SEPARATOR
    end

    def test_table_separator_constant
      assert_equal "__", DomainContext::TABLE_SEPARATOR
    end

    def test_table_suffix_constant
      assert_equal "_events", DomainContext::TABLE_SUFFIX
    end
  end
end
