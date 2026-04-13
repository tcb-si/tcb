# frozen_string_literal: true

require "active_record"
require "sqlite3"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: "file:tcb_test?mode=memory&cache=shared",
  flags: SQLite3::Constants::Open::URI | SQLite3::Constants::Open::READWRITE | SQLite3::Constants::Open::CREATE
)
