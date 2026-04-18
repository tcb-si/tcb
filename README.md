# TCB

A lightweight, thread-safe event and command runtime for Domain-Driven Design on Rails.

TCB gives Rails applications a clean domain language. Events, aggregates, and handlers are plain Ruby. No framework inheritance, no infrastructure details leaking into your domain.

TCB uses a command and event bus as an architectural coordination mechanism. Commands are decisions routed to exactly one handler. Events are facts broadcast to any number of reactions. The goal is to isolate side-effects, allow independent evolution of behaviors, and support an increasing number of business-significant events.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'tcb'
```

And then execute:

    $ bundle install

---

## Event Bus

The simplest use of TCB is a standalone pub/sub bus. Events are named in the past tense. They represent facts that have already happened:

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

### `TCB::HandlesEvents`

Instead of block handlers, reactions can be declared as classes inside a module. This keeps handlers close to the domain and readable at a glance.

```ruby
module Notifications
  include TCB::HandlesEvents

  on Auth::UserRegistered, react_with(SendWelcomeEmail, TrackRegistration)
  on Orders::OrderPlaced,  react_with(SendOrderConfirmation)
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

Event classes can come from anywhere. `TCB::HandlesEvents` only cares that they are published on the bus. Cross-module reactions are the norm, not the exception.

Register at configuration time:

```ruby
TCB.configure do |c|
  c.event_bus      = TCB::EventBus.new
  c.domain_modules = [Notifications]
end

TCB.publish(Auth::UserRegistered.new(id: 1, email: "alice@example.com"))
```

Handlers execute asynchronously in a background thread. Each handler is isolated. One failure does not prevent others from executing.

---

## TCB::HandlesCommands

Commands express intent. They are validated before execution and routed to an explicitly registered handler. One command, one handler. Commands are decisions, not broadcasts.

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
```

Use `TCB::HandlesCommands` to register the handler explicitly:

```ruby
module Orders
  include TCB::HandlesCommands

  # one command, one handler
  handle PlaceOrder, with(PlaceOrderHandler)
end

TCB.configure do |c|
  c.event_bus      = TCB::EventBus.new
  c.domain_modules = [Orders]
end

TCB.dispatch(PlaceOrder.new(order_id: 42, customer: "Alice"))
```

There is no convention-based routing. Every command handler is declared explicitly. Reading the module tells the whole story.

---

## Domain-Driven Design

Aggregates, persistence, and reactive handlers are where DDD gets complex. TCB keeps the domain language clean regardless. The infrastructure stays out of sight.

### Recommended file structure

Keep domain code together. TCB convention is a single `app/domain` folder. Beyond that, structure is yours to decide.

```
app/domain/
  orders.rb               # domain module, public interface
  orders/
    order.rb              # aggregate
    place_order_handler.rb
    reserve_inventory.rb
    charge_payment.rb
```

### The domain module

The domain module is a boundary. Everything inside speaks the domain language. Nothing leaks out, nothing bleeds in. Keep everything that belongs together, together. Events, commands, persistence rules, and reactions are all declared in one place:

```ruby
# app/domain/orders.rb
module Orders
  include TCB::Domain

  # Events
  OrderPlaced    = Data.define(:order_id, :customer)
  OrderCancelled = Data.define(:order_id, :reason)

  # Commands
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

  # Persistence
  persist events(
    OrderPlaced,
    OrderCancelled,
    stream_id_from_event: :order_id
  )

  # Commands
  handle PlaceOrder,  with(PlaceOrderHandler)
  handle CancelOrder, with(CancelOrderHandler)

  # Reactions
  on OrderPlaced,    react_with(ReserveInventory, ChargePayment)
  on OrderCancelled, react_with(RefundPayment)

  # Facade
  def self.place!(order_id:, customer:)
    TCB.dispatch(PlaceOrder.new(order_id: order_id, customer: customer))
  end

  def self.cancel!(order_id:, reason:)
    TCB.dispatch(CancelOrder.new(order_id: order_id, reason: reason))
  end
end
```

`TCB::Domain` includes both `TCB::HandlesEvents` and `TCB::HandlesCommands`. The full picture is visible in one place.

The facade is the public contract. Callers get plain method calls with meaningful names. TCB stays out of sight:

```ruby
Orders.place!(order_id: 42, customer: "Alice")
Orders.cancel!(order_id: 42, reason: "changed mind")
```

Facade methods use the bang convention. `TCB.dispatch` calls `validate!` on the command before routing it to the handler and raises if validation fails. Naming facade methods with `!` signals to callers that exceptions are expected.

### Aggregate

An aggregate is the consistency boundary around your domain state. It decides what is allowed and records what happened. TCB aggregates are plain Ruby objects. No base class, no persistence concerns.

The `TCB.record` block is the transactional boundary. Pass one aggregate or many. Either everything is persisted as it should be, or nothing is. The domain stays in a valid state.

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

The command handler is the entry point into the domain. This is where you ensure the domain stays in a valid state before announcing anything to the rest of the system. Persist first, publish after.

#### With aggregate

```ruby
# app/domain/orders/place_order_handler.rb
module Orders
  class PlaceOrderHandler
    def call(command)
      order = Order.new(id: command.order_id)

      # within: ApplicationRecord wraps the block in a database transaction.
      # If anything raises, no events are persisted and none are published.
      events = TCB.record(events_from: [order], within: ApplicationRecord) do
        order.place(customer: command.customer)
      end

      TCB.publish(*events)
    end
  end
end
```

**Persistence always happens before publishing.** If an exception is raised inside the block, no events are persisted and none are published. Omitting `within:` skips the transaction. Events are still collected and returned, but not persisted to the event store.

#### Without aggregate

When there is no aggregate, pass events directly:

```ruby
# app/domain/auth/register_handler.rb
module Auth
  class RegisterHandler
    def call(command)
      # within: ApplicationRecord wraps persistence in a transaction.
      # For a single event it is optional. But if you record multiple events,
      # use within: to ensure they are all persisted or none are.
      events = TCB.record(
        events: [UserRegistered.new(user_id: command.user_id, email_address: command.email_address, token: command.token)],
        within: ApplicationRecord
      )

      TCB.publish(*events)
    end
  end
end
```

#### Combined

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

**All events are persisted in a single transaction before any are published.**

---

## Configuration

Each domain module gets its own database table. Domains stay isolated at the persistence level. This is a step toward event sourcing. Every business-significant moment is recorded, queryable, and replayable.

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

Events are stored per aggregate stream. Query them by domain module and aggregate id. The result is always ordered by version. For large streams, `in_batches` uses keyset pagination and keeps memory usage flat.

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

# Batch processing
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

### ActiveRecord (YAML, all databases including SQLite)

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

### Domain module with event store

```bash
rails generate TCB:event_store orders place_order:order_id,customer cancel_order:order_id,reason
```

Generates:
- `app/domain/orders.rb`: domain module with commands, persistence placeholder, reactions placeholder, and facade
- `app/domain/orders/place_order_handler.rb`: command handler with `TCB.record` / `TCB.publish` scaffold
- `app/domain/orders/cancel_order_handler.rb`
- `db/migrate/TIMESTAMP_create_orders_events.rb`

### Domain module without persistence (pub/sub only)

```bash
rails generate TCB:domain notifications send_welcome_email:user_id,email send_verification_sms:user_id,phone
```

Generates:
- `app/domain/notifications.rb`: domain module with commands, reactions placeholder, and facade using `TCB.publish`
- `app/domain/notifications/send_welcome_email_handler.rb`
- `app/domain/notifications/send_verification_sms_handler.rb`

### Options

| Flag | Description |
|---|---|
| `--skip-domain` | Skip domain module and handlers |
| `--skip-migration` | Skip migration (event_store only) |
| `--no-comments` | Generate without inline guidance comments |

After generating, add your module to `config/initializers/tcb.rb`. This is the only place TCB needs to know about your domain modules. All reactions, persistence rules, and handler mappings are declared inside the module itself, not here:

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
  handle_signals: true,
  shutdown_timeout: 30.0
)

# Or manually
bus.shutdown(drain: true, timeout: 30.0)
bus.force_shutdown
```

---

## Testing

Use `TCB::EventStore::InMemory` in tests. TCB is designed so that `TCB.reset!` fully tears down and rebuilds the configuration between tests. It shuts down the event bus, clears the event store, and re-registers all handlers.

The `TCB.configure` block is stored and replayed on every `reset!`. Each test gets a fresh event bus and a clean event store automatically.

### Rails initializer

```ruby
# config/initializers/tcb.rb
Rails.application.config.to_prepare do
  TCB.configure do |c|
    c.event_bus   = TCB::EventBus.new(
      handle_signals: true,
      shutdown_timeout: 10.0
    )
    c.event_store = Rails.env.test? ? TCB::EventStore::InMemory.new
                                    : TCB::EventStore::ActiveRecord.new
    c.domain_modules = [Orders, Notifications]
  end
end
```

### RSpec

```ruby
# spec/support/tcb.rb
RSpec.configure do |config|
  config.include TCB::RSpecHelpers

  config.after(:each) do
    TCB.reset!
  end
end
```

Require it from `rails_helper.rb`:

```ruby
require "support/tcb"
```

`TCB.reset!` replays the configure block. `Rails.env.test?` is re-evaluated each time, so `InMemory` gets a fresh instance on every reset.

#### have_published

```ruby
expect { Orders.place!(order_id: 42, customer: "Alice") }.to have_published(Orders::OrderPlaced)
expect { Orders.place!(...) }.to have_published(Orders::OrderPlaced.new(order_id: 42, customer: "Alice"))
expect { Orders.place!(...) }.to have_published(Orders::OrderPlaced, within: 0.5)
```

#### poll_match

```ruby
expect { CALLED.include?(:reserve_inventory) }.to poll_match
expect { Payment.completed? }.to poll_match(within: 2.0)
```

### Minitest

```ruby
class OrdersTest < Minitest::Test
  include TCB::MinitestHelpers

  def teardown
    TCB.reset!
  end
end
```

#### assert_published

```ruby
assert_published(Orders::OrderPlaced) { Orders.place!(order_id: 42, customer: "Alice") }
assert_published(Orders::OrderPlaced.new(order_id: 42, customer: "Alice")) { Orders.place!(...) }
assert_published(Orders::OrderPlaced, Notifications::WelcomeEmailQueued) { Orders.place!(...) }
assert_published(Orders::OrderPlaced, within: 0.5) { Orders.place!(...) }
```

#### poll_assert

```ruby
poll_assert("handler was called") { CALLED.include?(:reserve_inventory) }
poll_assert("payment processed", within: 2.0) { Payment.completed? }
```

---

## Why `Data.define`

TCB uses Ruby's `Data.define` for events and commands throughout. This is a deliberate architectural choice, not a convention.

TCB embraces data coupling by design. Events carry only data, never behavior. This enables a reactive architecture where domain modules respond to facts rather than calling each other directly, keeping your codebase decoupled and easy to reason about.

**Immutability.** Events are facts. They cannot be changed after they happen. `Data.define` enforces this at the language level. There is no way to accidentally mutate an event in a handler.

**Explicit data coupling.** When you define `OrderPlaced = Data.define(:order_id, :customer)`, the attributes are the contract. Anyone reading the code sees exactly what an `OrderPlaced` event carries. No hidden state, no methods that obscure the data shape.

**Value semantics.** Two `OrderPlaced` events with the same attributes are equal. This makes testing straightforward. No mocks, no stubs, just plain equality assertions.

**No inheritance tax.** `Data.define` requires no base class, no framework module. Your domain events are pure Ruby. They can be used anywhere without pulling TCB along.

---

## Development

After checking out the repo, run `bundle install` to install dependencies. Then run `rake test` to run the tests.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/tcb-si/tcb.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
