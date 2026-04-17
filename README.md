# TCB

A lightweight, thread-safe event and command runtime for Domain-Driven Design on Rails.

TCB gives you a clean domain language that reads like pseudocode. Infrastructure details stay out of your domain. Events, aggregates, and handlers are plain Ruby with no framework inheritance.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'tcb'
```

And then execute:

    $ bundle install

---

## Event Bus

The simplest use of TCB is a standalone pub/sub bus. Events are named in the past tense — they represent facts that have already happened:

```ruby
UserRegistered = Data.define(:id, :email)
```

### Block handlers

```ruby
bus = TCB::EventBus.new

bus.subscribe(UserRegistered) do |event|
  WelcomeMailer.deliver(event.email)
end

bus.subscribe(UserRegistered) do |event|
  Analytics.track("user_registered", user_id: event.id)
end

bus.publish(UserRegistered.new(id: 1, email: "alice@example.com"))
```

### Class handlers with `TCB::HandlesEvents`

TCB is designed around a single architectural principle: a domain module should be understandable at a glance. Events, commands, persistence rules, and reactions belong together — not scattered across initializers, config files, and handler registries.

`TCB::HandlesEvents` is how you express reactions close to the domain. When you open `orders.rb`, you see exactly what happens when an `OrderPlaced` event is raised — no indirection, no magic, no hunting through config. The domain speaks for itself.

This works independently of aggregates and persistence — you can use `HandlesEvents` purely as a pub/sub mechanism:

```ruby
module Notifications
  include TCB::HandlesEvents

  on UserRegistered, execute(SendWelcomeEmail, TrackRegistration)
  on OrderPlaced,    execute(SendOrderConfirmation)
end

class SendWelcomeEmail
  def call(event)
    WelcomeMailer.deliver(event.email)
  end
end

class TrackRegistration
  def call(event)
    Analytics.track("user_registered", user_id: event.id)
  end
end
```

Register at configuration time:

```ruby
TCB.configure do |c|
  c.event_bus      = TCB::EventBus.new
  c.domain_modules = [Notifications]
end

TCB.publish(UserRegistered.new(id: 1, email: "alice@example.com"))
```

Handlers execute asynchronously in a background thread. Each handler is isolated — one failure does not prevent others from executing.

---

## Commands

Commands express intent. They are validated before execution and routed to a handler by convention (`PlaceOrder` → `PlaceOrderHandler`):

```ruby
PlaceOrder = Data.define(:order_id, :customer) do
  def validate!
    raise ArgumentError, "customer required" if customer.nil?
  end
end

class PlaceOrderHandler
  def call(command)
    # ... domain logic
  end
end

TCB.dispatch(PlaceOrder.new(order_id: 42, customer: "Alice"))
```

---

## Domain-Driven Design

For richer domains, TCB provides aggregates, event persistence, and reactive handlers — all expressed in a clean domain language.

### Recommended file structure

```
app/domain/
  orders.rb               # domain module — the public interface
  orders/
    order.rb              # aggregate
    place_order_handler.rb
    reserve_inventory.rb
    charge_payment.rb
```

### The domain module

Keep everything that belongs together, together. Events, commands, persistence rules, and reactions are all declared in one place:

```ruby
# app/domain/orders.rb
module Orders
  include TCB::HandlesEvents

  # Events — past tense, immutable facts
  OrderPlaced    = Data.define(:order_id, :customer)
  OrderCancelled = Data.define(:order_id, :reason)

  # Commands — present tense, expressed intent
  PlaceOrder  = Data.define(:order_id, :customer) do
    def validate!
      raise ArgumentError, "customer required" if customer.nil?
    end
  end

  CancelOrder = Data.define(:order_id, :reason) do
    def validate!
      raise ArgumentError, "reason required" if reason.nil?
    end
  end

  # Persistence — which events are stored and how to derive the stream
  persist events(
    OrderPlaced,
    OrderCancelled,
    stream_id_from_event: :order_id
  )

  # Reactions — which handlers fire for each event
  on OrderPlaced,    execute(ReserveInventory, ChargePayment)
  on OrderCancelled, execute(RefundPayment)

  # Facade — clean public interface, no TCB details leak out
  def self.place(order_id:, customer:)
    TCB.dispatch(PlaceOrder.new(order_id: order_id, customer: customer))
  end

  def self.cancel(order_id:, reason:)
    TCB.dispatch(CancelOrder.new(order_id: order_id, reason: reason))
  end
end
```

Callers interact with the domain through the facade — no infrastructure details leak out:

```ruby
Orders.place(order_id: 42, customer: "Alice")
Orders.cancel(order_id: 42, reason: "changed mind")
```

### Aggregate

```ruby
# app/domain/orders/order.rb
module Orders
  class Order
    include TCB::RecordsEvents

    attr_reader :id

    def initialize(id:) = @id = id

    def place(customer:)
      record OrderPlaced.new(order_id: id, customer: customer)
    end

    def cancel(reason:)
      record OrderCancelled.new(order_id: id, reason: reason)
    end
  end
end
```

### Command handler

#### With aggregate

```ruby
# app/domain/orders/place_order_handler.rb
module Orders
  class PlaceOrderHandler
    def call(command)
      order = Order.new(id: command.order_id)

      events = TCB.record(events_from: [order], within: ApplicationRecord) do
        order.place(customer: command.customer)
      end

      TCB.publish(*events)
    end
  end
end
```

**Persistence always happens before publishing.** If an exception is raised inside the block, no events are persisted and none are published.

#### Without aggregate

When there is no aggregate — no state to model, just a fact to record — pass events directly:

```ruby
# app/domain/auth/register_handler.rb
module Auth
  class RegisterHandler
    def call(command)
      events = TCB.record(
        events: [CustomerRegistered.new(user_id: command.user_id, email_address: command.email_address, token: command.token)],
        within: ApplicationRecord
      )

      TCB.publish(*events)
    end
  end
end
```

#### Combined — aggregate and direct events

When a single operation produces events from both an aggregate and a direct fact, pass both. Everything is persisted and published atomically:

```ruby
# app/domain/orders/place_order_handler.rb
module Orders
  class PlaceOrderHandler
    def call(command)
      order = Order.new(id: command.order_id)

      events = TCB.record(
        events_from: [order],
        events: [OrderingStarted.new(order_id: command.order_id, initiated_at: Time.now)],
        within: ApplicationRecord
      ) do
        order.place(customer: command.customer)
      end

      TCB.publish(*events)
    end
  end
end
```

**All events — from aggregates and direct — are persisted in a single transaction before any are published.**

---

## Configuration

Each domain module maps to its own database table, keeping domains isolated:

| Module | Table |
|---|---|
| `Orders` | `orders_events` |
| `Payments` | `payments_events` |
| `Payments::Charges` | `payments_charges_events` |

```ruby
TCB.configure do |c|
  c.event_bus      = TCB::EventBus.new
  c.event_store    = TCB::EventStore::ActiveRecord.new
  c.domain_modules = [Orders, Payments]

  # Optional: additional classes for YAML serialization
  c.extra_serialization_classes = [ActiveSupport::TimeWithZone, Money]
end
```

---

## Reading Events

```ruby
# All events for an aggregate
TCB.read(Orders).stream(42).to_a

# Version filters
TCB.read(Orders).stream(42).from_version(5).to_a
TCB.read(Orders).stream(42).to_version(20).to_a
TCB.read(Orders).stream(42).between_versions(5, 20).to_a

# Time filter
TCB.read(Orders).stream(42).occurred_after(1.week.ago).to_a

# Last N events (oldest first)
TCB.read(Orders).stream(42).last(10)

# Batch processing — keyset pagination, memory safe
TCB.read(Orders).stream(42).in_batches(of: 100) do |batch|
  batch.each { |envelope| replay(envelope.event) }
end

# With version bounds
TCB.read(Orders).stream(42).in_batches(of: 100, from_version: 50, to_version: 200) do |batch|
  # ...
end
```

Each result is a `TCB::Envelope`:

```ruby
envelope.event        # the domain event
envelope.event_id     # UUID string
envelope.stream_id    # "context|aggregate_id"
envelope.version      # integer, sequential per stream
envelope.occurred_at  # Time
```

---

## Event Store Adapters

### In-Memory (for tests)

```ruby
TCB::EventStore::InMemory.new
```

### ActiveRecord — YAML (text column, all databases including SQLite)

```ruby
TCB::EventStore::ActiveRecord.new
```

Generate migration and AR model:

```
bin/rails generate TCB:event_store orders
```

---

## Generators

TCB includes generators to scaffold domain modules, command handlers, and migrations.

### Install

```bash
rails generate TCB:install
```

Creates `config/initializers/tcb.rb` with a minimal configuration template.

---

### Domain module with event store

```bash
rails generate TCB:event_store orders place_order:order_id,customer cancel_order:order_id,reason
```

Generates:
- `app/domain/orders.rb` — domain module with commands, persistence placeholder, reactions placeholder, and facade
- `app/domain/orders/place_order_handler.rb` — command handler with `TCB.record` / `TCB.publish` scaffold
- `app/domain/orders/cancel_order_handler.rb`
- `db/migrate/TIMESTAMP_create_orders_events.rb`

---

### Domain module without persistence (pub/sub only)

```bash
rails generate TCB:domain notifications send_welcome_email:user_id,email send_verification_sms:user_id,phone
```

Generates:
- `app/domain/notifications.rb` — domain module with commands, reactions placeholder, and facade using `TCB.publish`
- `app/domain/notifications/send_welcome_email_handler.rb`
- `app/domain/notifications/send_verification_sms_handler.rb`

---

### Options

| Flag | Description |
|---|---|
| `--skip-domain` | Skip domain module and handlers |
| `--skip-migration` | Skip migration (event_store only) |
| `--no-comments` | Generate without inline guidance comments |

After generating, add your module to `config/initializers/tcb.rb`. This is the only place TCB needs to know about your domain modules — all reactions, persistence rules, and handler mappings are declared inside the module itself, not here:

```ruby
c.domain_modules = [
  Orders,
  Notifications,
]
```

---

## Error Handling

Failed handlers emit a `TCB::SubscriberInvocationFailed` event:

```ruby
TCB.config.event_bus.subscribe(TCB::SubscriberInvocationFailed) do |failure|
  Rails.logger.error "#{failure.error_class}: #{failure.error_message}"
  Rails.logger.error failure.error_backtrace.join("\n")
end
```

---

## Graceful Shutdown

```ruby
bus = TCB::EventBus.new(
  handle_signals: true,   # trap TERM and INT automatically
  shutdown_timeout: 30.0
)

# Or manually
bus.shutdown(drain: true, timeout: 30.0)
bus.force_shutdown
```

---

## Testing

Use `TCB::EventStore::InMemory` in tests.

### Minitest

Include `TCB::MinitestHelpers` in your test class:

```ruby
class OrdersTest < Minitest::Test
  include TCB::MinitestHelpers

  def setup
    TCB.configure do |c|
      c.event_bus   = TCB::EventBus.new
      c.event_store = TCB::EventStore::InMemory.new
      c.domain_modules = [Orders]
    end
  end

  def teardown
    TCB.reset!
  end
end
```

#### assert_published

```ruby
assert_published(Orders::OrderPlaced) { Orders.place(order_id: 42, customer: "Alice") }
assert_published(Orders::OrderPlaced.new(order_id: 42, customer: "Alice")) { Orders.place(...) }
assert_published(Orders::OrderPlaced, Notifications::WelcomeEmailQueued) { Orders.place(...) }
assert_published(Orders::OrderPlaced, within: 0.5) { Orders.place(...) }
```

#### poll_assert

```ruby
poll_assert("handler was called") { CALLED.include?(:reserve_inventory) }
poll_assert("payment processed", within: 2.0) { Payment.completed? }
```

### RSpec (experimental)

Include `TCB::RSpecHelpers` in your spec:

```ruby
RSpec.configure do |config|
  config.include TCB::RSpecHelpers

  config.before(:each) do
    TCB.reset!
  end
end
```

#### have_published

```ruby
expect { Orders.place(order_id: 42, customer: "Alice") }.to have_published(Orders::OrderPlaced)
expect { Orders.place(...) }.to have_published(Orders::OrderPlaced.new(order_id: 42, customer: "Alice"))
expect { Orders.place(...) }.to have_published(Orders::OrderPlaced, within: 0.5)
```

#### poll_match

```ruby
expect { CALLED.include?(:reserve_inventory) }.to poll_match
expect { Payment.completed? }.to poll_match(within: 2.0)
```

---

## Why `Data.define`

TCB uses Ruby's `Data.define` for events and commands throughout. This is a deliberate architectural choice, not a convention.

TCB embraces data coupling by design — events carry only data, never behavior. This enables a reactive architecture where domain modules respond to facts rather than calling each other directly, keeping your codebase decoupled and easy to reason about.

**Immutability.** Events are facts — they cannot be changed after they happen. `Data.define` enforces this at the language level. There is no way to accidentally mutate an event in a handler.

**Explicit data coupling.** When you define `OrderPlaced = Data.define(:order_id, :customer)`, the attributes are the contract. Anyone reading the code sees exactly what an `OrderPlaced` event carries — no hidden state, no methods that obscure the data shape.

**Value semantics.** Two `OrderPlaced` events with the same attributes are equal. This makes testing straightforward — no mocks, no stubs, just plain equality assertions.

**No inheritance tax.** `Data.define` requires no base class, no framework module. Your domain events are pure Ruby — they can be used anywhere without pulling TCB along.

---

## Development

After checking out the repo, run `bundle install` to install dependencies. Then run `rake test` to run the tests.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/tcb-si/tcb.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
