# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `TCB.configured?` — predicate to check if TCB has been configured
- `TCB.reset!(graceful_shutdown_time:)` — optional graceful bus drain before reset; defaults to `force_shutdown`

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
