# SLG-0007: Scoped logger factory

Modify `LoggingSystem.factory` to consult a task-local handler factory before falling back to the bootstrapped
one. A caller binds the task-local via `withLoggerFactory(_:_:)` to scope a logging backend to a subsystem or a
test, without mutating the process-wide bootstrap.

## Overview

- Proposal: SLG-0007
- Author(s): [Vladimir Kukushkin](https://github.com/kukushechkin)
- Status: **Awaiting Review**
- Issue: [apple/swift-log#261](https://github.com/apple/swift-log/issues/261)
- Implementation: [apple/swift-log#XXX](https://github.com/apple/swift-log/pull/XXX)
- Feature flag: none
- Related links:
    - [Lightweight proposals process description](https://github.com/apple/swift-log/blob/main/Sources/Logging/Docs.docc/Proposals/Proposals.md)
    - [SLG-0006: Task-local Logger extensions](SLG-0006-task-local-logger.md)

### Introduction

The handler used by `Logger.init(label:)` is either the process-wide one set by `LoggingSystem.bootstrap`, or the
per-construction override on `Logger.init(label:factory:)`. Neither is scoped: `bootstrap` is global, and the
per-construction override only affects the single `Logger` it produces, which then has to be threaded through every
API that wants to honour it.

This proposal adds a complementary scoped mechanism: bind a factory for the duration of a structured-concurrency
scope, restore the previous one on exit. Inside the scope, every `Logger(label:)` constructed in the call tree uses
the scoped factory.

### Motivation

A test that wants to capture log output from library code today has to bootstrap:

```swift
@Test func myFeatureLogsTheRightThings() async throws {
    let captured = InMemoryLogStorage()
    LoggingSystem.bootstrap { label in
        InMemoryLogHandler(label: label, storage: captured)
    }
    try await runFeature()
    #expect(captured.entries.contains(where: { $0.message == "feature done" }))
}
```

`LoggingSystem.bootstrap` is one-shot and process-wide. Tests running concurrently observe each other's handlers,
and the bootstrap state leaks between cases.

A caller that wants downstream code to use a specific backend can construct a `Logger` with an explicit factory
via `Logger.init(label:factory:)` and pass it in:

```swift
let logger = Logger(label: "subsystem") { _ in NullLogHandler(label: $0) }
externalSystemCall(logger: logger)
```

But that only helps code that accepts the `Logger` as a parameter. The override has to be threaded through every
layer of the call tree that wants to honour it; library code inside `externalSystemCall` that constructs its own
`Logger(label: …)` goes through the bootstrapped factory and ignores the override.

There is no way today to scope a different factory for *every* `Logger.init(label:)` constructed in a structured
block — without threading a `Logger` through every API or mutating the process-wide bootstrap.

### Proposed solution

Modify `LoggingSystem.factory` so it returns the task-local-bound factory when one is in effect, and the
bootstrapped factory otherwise. `Logger.init(label:)` is unchanged in shape — it still calls
`LoggingSystem.factory` — and so picks up the scoped value automatically. `withLoggerFactory(_:_:)` binds the
task-local for a structured scope:

```swift
@main
struct MyServer {
    static func main() async throws {
        try await withLoggerFactory(StreamLogHandler.standardError) {
            try await ServiceGroup(...).run()
        }
    }
}
```

`LoggingSystem.factory` becomes public — it's now the canonical "the factory currently in effect" accessor,
useful for composing wrappers on top of whatever is in scope. Outside any `withLoggerFactory(_:_:)` scope it
returns the bootstrapped factory, matching the pre-SLG-0007 behaviour verbatim.

### Detailed design

```swift
extension LoggingSystem {
    /// The handler factory currently in effect for this task — the value bound by the
    /// nearest enclosing ``withLoggerFactory(_:_:)`` scope, or the bootstrapped factory
    /// when no scope is active.
    public static var factory: @Sendable (String, Logger.MetadataProvider?) -> any LogHandler
}

extension Logger {
    /// Task-local storage for the handler factory. Bound by ``withLoggerFactory(_:_:)``;
    /// `LoggingSystem/factory` reads this and falls back to the bootstrapped factory when
    /// nil. Task-local values propagate through structured concurrency (`async let`,
    /// `withTaskGroup`, child `Task { }`) but are **not** inherited by `Task.detached`.
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    internal static let taskLocalFactory:
        TaskLocal<(@Sendable (String, Logger.MetadataProvider?) -> any LogHandler)?>
}

/// Bind `factory` as the handler factory for the current scope. `Logger.init(label:)`
/// calls within `operation` receive a handler built by `factory`. Nested scopes replace
/// the outer factory for the inner scope.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public func withLoggerFactory<Result>(
    _ factory: @escaping @Sendable (String, Logger.MetadataProvider?) -> any LogHandler,
    _ operation: () throws -> Result
) rethrows -> Result

/// Async variant of ``withLoggerFactory(_:_:)``.
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
public func withLoggerFactory<Result>(
    _ factory: @escaping @Sendable (String, Logger.MetadataProvider?) -> any LogHandler,
    _ operation: nonisolated(nonsending) () async throws -> Result
) async rethrows -> Result
```

`Logger.init(label:)` is unchanged in shape — it just calls `LoggingSystem.factory`, which now does the task-local
lookup itself:

```swift
public init(label: String) {
    self.init(label: label, LoggingSystem.factory(label, LoggingSystem.metadataProvider))
}
```

`LoggingSystem.factory` does one task-local read on the read path. Outside any scope, the read returns nil and
falls back to the bootstrapped factory — matching pre-SLG-0007 behaviour exactly.

### API stability

- **`Logger.init(label:)` signature** unchanged. Behaviour changes only inside a `withLoggerFactory(_:_:)` scope,
  which requires explicit opt-in.
- **No changes** required to `LogHandler` implementations.
- **`LoggingSystem.bootstrap`** continues to work unchanged. The task-local wins inside its scope; outside, the
  bootstrap factory is returned as before.
- **`LoggingSystem.factory` is now public** (previously internal). Its semantic shifts from "the bootstrapped
  factory" to "the factory currently in effect" — i.e., the task-local-bound one when a scope is active, the
  bootstrapped one otherwise. There were no public callers of the previous internal accessor.
- **Performance.** `LoggingSystem.factory` adds one task-local read per call — *unconditionally*, including in
  codebases that never call `withLoggerFactory(_:_:)`. The read walks the calling task's binding-list, so cost is
  O(N) in the depth of currently-bound task-locals of any kind; outside any binding it's a couple of dependent
  loads plus a branch. Inside a scope, the bound factory closure is read via one atomic retain/release per call.
  Benchmarks under `Benchmarks/NoTraits` cover this. Hot paths that construct many short-lived loggers retain the
  explicit `Logger`-as-parameter pattern from <doc:003-AcceptingLoggers>.
- **Source compatibility.** `withLoggerFactory` is a new top-level name. Codebases defining their own would need
  to fully qualify or rename.

### Future directions

- **`TaskLocal<Logger>.withLoggerFactory(_:_:)` extension.** Sugar combining a factory swap with a rebuild of the
  bound task-local logger, so callers don't have to nest `withLoggerFactory(...)` inside
  `someTaskLocal.withValue(Logger(label: ""))` manually. Equivalent to that nested form; deferred.
- **`withLoggerLogLevel(_:_:)` free function.** Wraps the current factory with one that returns handlers at the
  given `Logger.Level`. Composes with `withLoggerFactory(_:_:)`: the new factory delegates via
  `LoggingSystem.factory` and adjusts the level on each handler it produces.

### Alternatives considered

#### Add a separate `Logger.factory` public accessor instead of modifying `LoggingSystem.factory`

Keep `LoggingSystem.factory` as "the bootstrapped factory" and introduce a parallel `Logger.factory` accessor
that returns "the currently-effective factory" (task-local or bootstrap). Rejected because the two would behave
identically outside any scope and differently inside one — the duplicated surface adds noise without adding
expressivity. `LoggingSystem.factory` was previously internal, so re-pointing its public name at the
currently-effective factory has no callers to break, and the semantic ("the factory swift-log will use right now")
matches what users want when composing wrappers.

#### Use `ServiceContext` from swift-distributed-tracing as the storage

Store the factory in `ServiceContext`. Rejected because `ServiceContext` carries distributed correlation data that
flows across process boundaries (trace IDs, span IDs, baggage); the handler factory is process-local and should
never cross the wire. The two systems compose at a different layer: `MetadataProvider` reads `ServiceContext` at
emission time, while `withLoggerFactory(_:_:)` scopes the `(label, provider) -> handler` *binding* itself — the
provider is captured when the factory runs (i.e., at handler construction), so a scoped factory layered on top of
the system one is the correct seam for installing a per-scope provider.
