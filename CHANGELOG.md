# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `TCB::Envelope` — unified primitive replacing `TCB::EventStore::EventStreamEnvelope`; carries `event`, `event_id`, `stream_id`, `version`, `occurred_at`, `correlation_id`, `causation_id`
- `TCB::Envelope.wrap(event, correlation_id:, causation_id:)` — factory for wrapping bare events into envelopes with auto-generated `event_id` and `occurred_at`
- `TCB::Envelope.coerce(event_or_envelope)` — idempotent coercion; returns envelope unchanged, wraps bare events
- `TCB.dispatch(command, correlation_id:)` — accepts optional `correlation_id`; generates `SecureRandom.uuid` by default; propagates through all envelopes produced within the command handler
- `causation_id` propagation — reactive handlers registered via `on / react_with` automatically receive `causation_id` set to the `event_id` of the triggering envelope; fully transparent, no handler interface change
- `TCB::EventStore::InMemory#append` — accepts `correlation_id:` and `causation_id:`; stores on envelope
- `TCB::EventStore::ActiveRecord#append` — accepts `correlation_id:` and `causation_id:`; persists to DB columns
- Migration template — adds `correlation_id`, `causation_id` columns and indexes on `event_id` and `correlation_id`
- `TCB::EventBus.new(sync: false)` — opt-in synchronous execution mode; handlers execute in caller thread, no dispatcher thread started, no polling required in tests
- `TCB::EventBus.new(max_queue_size:, high_water_mark:)` — opt-in queue pressure signalling; emits `TCB::EventBusQueuePressure` event once per threshold crossing when queue depth reaches or exceeds `high_water_mark`
- `TCB::EventBus.new(max_queue_size:)` — opt-in bounded queue via `SizedQueue`; publish blocks caller thread when queue is full, providing explicit backpressure signal
- `TCB.configured?` — returns `false` if config does not exist or `event_bus` is not set
- `TCB.reset!(graceful_shutdown_time:)` — optional graceful bus drain before reset; defaults to `force_shutdown`
- `TCB.domain_modules=` — declare bounded contexts separately from infrastructure configuration
- `Configuration#event_bus_configured?` — predicate used internally by `TCB.configured?`
- `EventBus#initialize` — dispatcher thread setup extracted to `RunningStrategy#start`; signal handler setup extracted to private `install_signal_handlers`
- `RunningStrategy` — accepts `sync:` keyword; `start` method owns dispatcher thread lifecycle; `build_pressure_event` moved from `EventBus` into `RunningStrategy`
- `ShutdownStrategy` — `force_terminate` and `terminate_dispatcher` are no-op when dispatcher is nil (sync mode)

### Changed

- `TCB.record` — now returns envelopes instead of bare events; callers use `envelopes.map(&:event)` to access domain events
- `TCB.publish` — accepts envelopes or bare events; bare events are wrapped via `Envelope.coerce`
- `TCB::EventBus#dispatch` — accepts envelopes or bare events; coerces internally
- `TCB::EventBus#execute_handler` — passes full envelope to handler blocks; `flush_domain_modules` subscription blocks unpack `envelope.event` before calling domain handlers
- `TCB.configure` — now configures infrastructure only (event bus, event store); domain modules declared separately via `TCB.domain_modules=`
- `TCB.reset!` — no longer replays configure block; caller is responsible for reconfiguring after reset
- `TCB.record` — `within:` gracefully ignored if object does not respond to `.transaction`

### Removed

- `TCB::EventStore::EventStreamEnvelope` — replaced by `TCB::Envelope`
- `TCB.configure` with `domain_modules:` as a single all-in-one configuration block — replaced by `TCB.domain_modules=` + `TCB.configure`

## [0.5.0] - 2026-04-14

### Added

- `TCB::EventBus` — thread-safe, async pub/sub bus with graceful shutdown
- `TCB::RecordsEvents` — aggregate mixin for recording domain events
- `TCB.record` — transaction boundary, returns recorded events
- `TCB.publish` — explicit, caller-controlled event publication
- `TCB.dispatch` — command bus with `validate!` convention and handler routing
- `TCB::HandlesEvents` — declarative event reactions with `on / execute` DSL
- `TCB::Configuration` — composition root, frozen after configuration
- `TCB::EventStore::InMemory` — in-memory event store for tests
- `TCB::EventStore::ActiveRecord` — ActiveRecord persistence adapter (YAML, SQLite compatible)
- `TCB::EventQuery` — fluent read API with version and time filters
- `TCB::TestHelpers` — Minitest helpers: `assert_published`, `poll_assert`
- `TCB::TestHelpers::RSpec` — RSpec matchers: `have_published`, `poll_assert`
- Rails generators: `tcb:install`, `tcb:event_store`, `tcb:domain`
- `EventBus#unsubscribe`
