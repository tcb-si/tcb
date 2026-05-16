# frozen_string_literal: true

require_relative "active_record_setup"

module Invoicing
  class OutboxRecord < ActiveRecord::Base
    self.table_name  = "tcb__outbox_store__active_record_test__invoicing_outbox"
    self.primary_key = "id"
  end
end
