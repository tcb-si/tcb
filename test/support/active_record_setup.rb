# frozen_string_literal: true

require "active_record"
require "sqlite3"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: "file:tcb_test?mode=memory&cache=shared",
  flags: SQLite3::Constants::Open::URI | SQLite3::Constants::Open::READWRITE | SQLite3::Constants::Open::CREATE
)

ActiveRecord::Schema.define do
  create_table :orders_events, force: :cascade do |t|
    t.string   :event_id,    null: false
    t.string   :stream_id,   null: false
    t.integer  :version,     null: false
    t.string   :event_type,  null: false
    t.text     :payload,     null: false
    t.datetime :occurred_at, null: false
  end

  add_index :orders_events, [:stream_id, :version], unique: true
end

module Orders
  class EventRecord < ActiveRecord::Base
    self.table_name = "orders_events"
  end
end
