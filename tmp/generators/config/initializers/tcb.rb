TCB.configure do |c|
  c.event_bus   = TCB::EventBus.new
  c.event_store = TCB::EventStore::ActiveRecord.new # In tests, use TCB::EventStore::InMemory.new instead.

  # Add your domain modules here after generating them:
  #   rails generate tcb:event_store orders place_order:order_id,customer
  #   rails generate tcb:domain notifications send_welcome_email:user_id,email
  c.event_handlers = [
    # Orders
  ]
end
