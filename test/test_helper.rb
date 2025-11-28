# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'tcb-events'
require_relative 'support/event_bus_dsl'

# Define sample event classes for testing
UserRegistered = Data.define(:id, :email)
OrderPlaced = Data.define(:order_id, :total)
PaymentProcessed = Data.define(:order_id, :amount)