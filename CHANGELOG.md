# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-04-24

### Added

- `TCB.read_correlation(correlation_id, across: [...])` — cross-domain correlation query; returns all envelopes with the given `correlation_id` across specified domains, ordered by `occurred_at`; `across:` is optional, defaults to all domains with persistence registrations; supports `occurred_after`, `occurred_before`, `between` filters
- `TCB::CorrelationQuery` — fluent interface for correlation queries with `occurred_after`, `occurred_before`, `between`, `to_a`
- `TCB::EventStore::InMemory#read_by_correlation` — correlation query support for in-memory store
- `TCB::EventStore::ActiveRecord#read_by_correlation` — correlation query support via SQL UNION across domain tables
- `TCB::Envelope` — unified primitive replacing `TCB::EventStore::EventStreamEnvelope`; carries `event`, `event_id`, `stream_id`, `version`, `occurred_at`, `correlation_id`, `causation_id`
- `TCB::Envelope.wrap(event, correlation_id:, causation_id:)` — factory for wrapping bare events into envelopes with auto-generated `event_id` and `occurred_at`
- `TCB::Envelope.coerce(event_or_envelope)` — idempotent coercion; returns envelope unchanged, wraps bare events
- `TCB.dispatch(command, correlation_id:)` — returns `correlation_id` (String); accepts optional override, generates `SecureRandom.uuid` by default
- `correlation_id` propagation — all envelopes produced within a dispatch share the same `correlation_id`; propagates across thread boundary via envelope data, not execution state
- `causation_id` propagation — reactive handlers registered via `on / react_with` automatically set `causation_id` to the `event_id` of the triggering envelope; handler interface unchanged (`def call(event)`)
- `TCB::EventStore::InMemory#append` — accepts `correlation_id:` and `causation_id:`
- `TCB::EventStore::ActiveRecord#append` — accepts `correlation_id:` and `causation_id:`; persists to DB columns
- Migration template — adds `correlation_id`, `causation_id` columns with indexes on `event_id` and `correlation_id`
- `TCB::EventBus.new(sync:)` — synchronous execution mode; handlers execute in caller thread, no dispatcher thread, no polling in tests
- `TCB::EventBus.new(max_queue_size:, high_water_mark:)` — bounded queue with pressure signalling; emits `TCB::EventBusQueuePressure` on threshold crossing
- `TCB.configured?` — returns `false` if config does not exist or `event_bus` is not set
- `TCB.reset!(graceful_shutdown_time:)` — optional graceful bus drain before reset
- `TCB.domain_modules=` — declare bounded contexts separately from infrastructure configuration

### Changed

- `TCB.record` — returns envelopes instead of bare events; use `envelopes.map(&:event)` to access domain events
- `TCB.publish` — accepts envelopes or bare events; bare events wrapped via `Envelope.coerce`
- `TCB.configure` — configures infrastructure only; domain modules declared separately via `TCB.domain_modules=`
- `TCB.reset!` — no longer replays configure block; caller responsible for reconfiguring after reset

### Removed

- `TCB::EventStore::EventStreamEnvelope` — replaced by `TCB::Envelope`
- `TCB.configure` with `domain_modules:` keyword — replaced by `TCB.domain_modules=` + `TCB.configure`

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
