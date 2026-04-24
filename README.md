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

### Execution model

TCB::EventBus uses a single background thread to process events. Publishing is non-blocking — the event is placed on a queue and control returns to the caller immediately. The dispatcher thread processes events in FIFO order. Handlers for a given event execute sequentially within the dispatcher thread.

This design favors determinism and simplicity: events are always processed in the order they were published, and handlers cannot race with each other.

For tests and simple use cases, `sync: true` executes handlers in the caller thread immediately — no background thread, no queue:

```ruby
bus = TCB::EventBus.new(sync: true)
```

### Delivery guarantees

TCB guarantees:
- Events published to the bus will be dispatched to all registered handlers, in the order they were published, as long as the process remains alive.
- If `TCB.record` is used before `TCB.publish`, events are persisted to the event store before any handler runs.

TCB does not guarantee:
- That published events will be processed if the process crashes after publish but before handlers complete.
- At-least-once, at-most-once, or exactly-once delivery.
- Retry on handler failure. Failed handlers emit `TCB::SubscriberInvocationFailed`. Retry is the responsibility of the application.

If stronger delivery guarantees are required, use a durable external queue (SolidQueue, Sidekiq, etc.) and trigger TCB handlers from jobs.

### Backpressure

The event queue is unbounded by default. If handlers are slower than the rate of publishing, the queue will grow without limit. For production systems under sustained load, set `max_queue_size:` to apply backpressure:

```ruby
TCB::EventBus.new(max_queue_size: 10_000)
```

When the queue is full, `publish` blocks until space is available. The right value depends on your event volume and handler latency — measure before deciding.

---

## TCB::HandlesEvents

Instead of block handlers, reactions can be declared as classes inside a module. This keeps handlers close to the domain and readable at a glance.

```ruby
# app/domain/warehouse.rb
module Warehouse
  include TCB::Domain

  StockReserved = Data.define(:order_id)

  persist events(
    StockReserved,
    stream_id_from_event: :order_id
  )

  on Sales::OrderPlaced, react_with(ReserveStock)
end

# app/domain/warehouse/reserve_stock.rb
module Warehouse
  class ReserveStock
    def call(event)
      stock = Stock.new(id: event.order_id)

      events = TCB.record(events_from: [stock], within: ApplicationRecord) do
        stock.reserve
      end

      TCB.publish(*events)
    end
  end
end
```

```ruby
# app/domain/notifications.rb
module Notifications
  include TCB::HandlesEvents

  on Warehouse::StockReserved, react_with(NotifyCustomer)
end

# app/domain/notifications/notify_customer.rb
module Notifications
  class NotifyCustomer
    def call(event)
      events = TCB.record(events: [CustomerNotified.new(order_id: event.order_id)])
      TCB.publish(*events)
    end
  end

  CustomerNotified = Data.define(:order_id)
end
```

Event classes can come from anywhere. Cross-module reactions are the norm, not the exception. Each handler is isolated. Ine failure does not prevent others from executing.

Domain modules are declared once at the top level, before infrastructure is configured.
This is the only place TCB needs to know about your bounded contexts — all reactions,
persistence rules, and handler mappings live inside each module itself.

```ruby
TCB.domain_modules = [Sales, Warehouse, Notifications]

TCB.configure do |c|
  c.event_bus   = TCB::EventBus.new
  c.event_store = TCB::EventStore::ActiveRecord.new
end
```

`TCB.domain_modules=` wires up subscriptions and command routing from all modules.
`TCB.configure` provides the infrastructure they run on. The two are intentionally
separate — domain modules don't change between environments, infrastructure does.

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

TCB.domain_modules = [ Orders ]
TCB.configure do |c|
  c.event_bus = TCB::EventBus.new
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
  sales.rb                      # domain module, public interface
  sales/
    order.rb                    # aggregate
    place_order_handler.rb
  warehouse.rb
  warehouse/
    reserve_stock.rb
  notifications.rb
  notifications/
    notify_customer.rb
```

### The domain module

The domain module is a boundary. Everything inside speaks the domain language. Nothing leaks out, nothing bleeds in. Keep everything that belongs together, together. Events, commands, persistence rules, and reactions are all declared in one place:

```ruby
# app/domain/sales.rb
module Sales
  include TCB::Domain

  # Facade
  def self.place!(order_id:, customer:)
    TCB.dispatch(PlaceOrder.new(order_id: order_id, customer: customer))
  end

  # Events
  OrderPlaced = Data.define(:order_id, :customer)

  # Commands
  PlaceOrder = Data.define(:order_id, :customer) do
    def validate!
      raise ArgumentError, "customer required" if customer.nil?
    end
  end

  # Persistence
  persist events(
    OrderPlaced,
    stream_id_from_event: :order_id
  )

  # Commands
  handle PlaceOrder, with(PlaceOrderHandler)

  # Reactions
  on OrderPlaced, react_with(Warehouse::ReserveStock)
end
```

`TCB::Domain` includes both `TCB::HandlesEvents` and `TCB::HandlesCommands`. The full picture is visible in one place.

The facade is the public contract. Callers get plain method calls with meaningful names. TCB stays out of sight:

```ruby
Sales.place!(order_id: 42, customer: "Alice")
```

Facade methods use the bang convention. `TCB.dispatch` calls `validate!` on the command before routing it to the handler and raises if validation fails. Naming facade methods with `!` signals to callers that exceptions are expected.

### Aggregate

An aggregate is the consistency boundary around your domain state. It decides what is allowed and records what happened. TCB aggregates are plain Ruby objects. No base class, no persistence concerns.

The `TCB.record` block is the transactional boundary. Pass one aggregate or many. Either everything is persisted as it should be, or nothing is. The domain stays in a valid state.

```ruby
# app/domain/sales/order.rb
module Sales
  class Order
    include TCB::RecordsEvents

    attr_reader :id

    def initialize(id:) = @id = id

    def place(customer:)
      record OrderPlaced.new(order_id: id, customer: customer)
    end
  end
end
```

### Command handler

The command handler is the entry point into the domain. This is where you ensure the domain stays in a valid state before announcing anything to the rest of the system. Persist first, publish after.

```ruby
# app/domain/sales/place_order_handler.rb
module Sales
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

### Domain modules

Domain modules are the bounded contexts of your application. Declare them once, at the top level — before infrastructure is configured:

```ruby
# config/initializers/tcb.rb
TCB.domain_modules = [Orders, Notifications]
```

This is the only place TCB needs to know about your domain modules. All reactions, persistence rules, and handler mappings are declared inside each module itself.

### Infrastructure

Infrastructure is environment-specific. Configure it in each environment file so the differences are explicit and co-located with other environment settings:

```ruby
# config/environments/development.rb
Rails.application.config.to_prepare do
  TCB.reset!
  TCB.configure do |c|
    c.event_bus   = TCB::EventBus.new(
      handle_signals: false,   # Rails manages process signals in development
      shutdown_timeout: 10.0
    )
    c.event_store = TCB::EventStore::ActiveRecord.new
  end
end
```

`to_prepare` runs after every Rails reload. `TCB.reset!` shuts down the previous bus before configuring a new one. Without it, each reload would leak a dispatcher thread.

```ruby
# config/environments/production.rb
Rails.application.config.to_prepare do
  TCB.reset!(graceful_shutdown_time: 10.0)
  TCB.configure do |c|
    c.event_bus   = TCB::EventBus.new(
      handle_signals: true,
      shutdown_timeout: 30.0
    )
    c.event_store = TCB::EventStore::ActiveRecord.new
  end
end
```

`handle_signals: true` installs SIGTERM/SIGINT handlers for graceful shutdown. `graceful_shutdown_time` on `reset!` gives the previous bus time to drain before replacing it.

```ruby
# config/environments/test.rb
Rails.application.config.after_initialize do
  TCB.configure do |c|
    c.event_bus   = TCB::EventBus.new(sync: true)
    c.event_store = TCB::EventStore::InMemory.new
  end
end
```

`sync: true` executes handlers in the caller thread — no background thread, no polling. `after_initialize` runs once at boot. Between tests, call `TCB.reset!` to get a fresh bus and store.

Each domain module gets its own database table. Domains stay isolated at the persistence level:

| Module | Table |
|---|---|
| `Orders` | `orders_events` |
| `Payments` | `payments_events` |
| `Payments::Charges` | `payments_charges_events` |

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
envelope.event          # the domain event
envelope.event_id       # UUID string
envelope.stream_id      # "context|aggregate_id"
envelope.version        # integer, sequential per stream
envelope.occurred_at    # Time
envelope.correlation_id # UUID string, shared across all events in a dispatch chain
envelope.causation_id   # UUID string, event_id of the triggering event; nil for the first event
```

---

## Correlation and causation tracking

Every `TCB.dispatch` generates a `correlation_id` and returns it to the caller. All events produced within that dispatch chain share the same `correlation_id`, regardless of how deep the reactive chain goes. `causation_id` identifies the direct cause — the `event_id` of the envelope that triggered the handler.

```
Sales.place!(order_id: 42, customer: "Alice")
  └─ Sales::OrderPlaced            correlation_id: "req-abc", causation_id: nil
      └─ Warehouse::StockReserved      correlation_id: "req-abc", causation_id: OrderPlaced.event_id
          └─ Notifications::CustomerNotified  correlation_id: "req-abc", causation_id: StockReserved.event_id
```

`correlation_id` can be provided externally. That's useful for tying a dispatch to an incoming HTTP request:

```ruby
correlation_id = TCB.dispatch(
  Sales::PlaceOrder.new(order_id: 42, customer: "Alice"),
  correlation_id: request.uuid
)
response.set_header("X-Correlation-ID", correlation_id)
```

`correlation_id` and `causation_id` are set by `TCB.record`, not by `TCB.publish`. A handler that calls `TCB.record` within a reactive chain will always have both fields populated. A handler that only calls `TCB.publish` without `TCB.record` produces envelopes without these fields. There is no event store context to propagate from.

Handler interfaces are unchanged. `def call(event)` receives the domain event as always. Correlation and causation travel in the envelope, not in your domain code.

Events recorded outside a dispatch context (directly via `TCB.record` without a preceding `TCB.dispatch`) have `nil` for both fields. This is expected: there is no dispatch to correlate them to.

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

After generating, add your module to config/initializers/tcb.rb. Domain modules don't change between environments — infrastructure does. Keeping them separate means your bounded contexts are declared once, while the bus and store are configured per environment:

```ruby
# config/initializers/tcb.rb
TCB.domain_modules = [
  Sales,
  Warehouse,
  Notifications
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

### Setup

Configure TCB once at boot in `config/environments/test.rb` (see Configuration above). Between tests, call `TCB.reset!` to get a fresh event bus and a clean event store.

`TCB.reset!` shuts down the current bus, clears the event store, and clears all subscriptions. The next test starts with a clean slate. Domain modules do not need to be re-declared — they are set once at the top level and persist across resets.

### Synchronous mode

With `sync: true`, handlers execute in the caller thread immediately after `publish`. No background thread, no polling, no timing concerns. Tests are faster and deterministic. This is the recommended approach.

```ruby
# config/environments/test.rb
Rails.application.config.after_initialize do
  TCB.configure do |c|
    c.event_bus   = TCB::EventBus.new(sync: true)
    c.event_store = TCB::EventStore::InMemory.new
  end
end
```

### Minitest

```ruby
class OrdersTest < Minitest::Test
  include TCB::MinitestHelpers
  def teardown = TCB.reset!

  def test_placing_order_publishes_event
    assert_published(Orders::OrderPlaced) do
      Orders.place!(order_id: 42, customer: "Alice")
    end
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

Only needed when using an async bus. With `TCB::EventBus.new(sync: true)`, handlers execute in the caller thread and results are available immediately — no polling required.

```ruby
poll_assert("reserve inventory called") { CALLED.include?(:reserve_inventory) }
poll_assert("payment processed", within: 2.0) { Payment.completed? }
```

### RSpec

```ruby
# spec/support/tcb.rb
RSpec.configure do |config|
  config.after(:each) { TCB.reset! }
end
```

Require it from `rails_helper.rb`:

```ruby
require "support/tcb"
```

#### have_published

```ruby
expect { Orders.place!(order_id: 42, customer: "Alice") }.to have_published(Orders::OrderPlaced)
expect { Orders.place!(...) }.to have_published(Orders::OrderPlaced.new(order_id: 42, customer: "Alice"))
expect { Orders.place!(...) }.to have_published(Orders::OrderPlaced, within: 0.5)
```

#### poll_match

Only needed with an async bus.

```ruby
expect { CALLED.include?(:reserve_inventory) }.to poll_match
expect { Payment.completed? }.to poll_match(within: 2.0)
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
