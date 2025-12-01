# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'tcb-events'
require_relative 'support/event_bus_dsl'
require "minitest/reporters"
require "debug"

Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new, Minitest::Reporters::ProgressReporter.new]

# Define sample event classes for testing
UserRegistered = Data.define(:id, :email)
OrderPlaced = Data.define(:order_id, :total)
PaymentProcessed = Data.define(:order_id, :amount)
