# SLG-0006: Task-local Logger extensions

Provide a generic `TaskLocal<Logger>` extension API to merge metadata onto and emit logs through, so a module
can declare a scoped logger once and call it directly without threading a `Logger` parameter through every internal API.

## Overview

- Proposal: SLG-0006
- Author(s): [Vladimir Kukushkin](https://github.com/kukushechkin)
- Status: **Awaiting Review**
- Issue: [apple/swift-log#261](https://github.com/apple/swift-log/issues/261)
- Implementation: [apple/swift-log#XXX](https://github.com/apple/swift-log/pull/XXX)
- Feature flag: none
- Related links:
    - [Lightweight proposals process description](https://github.com/apple/swift-log/blob/main/Sources/Logging/Docs.docc/Proposals/Proposals.md)
    - [SLG-0001: Metadata Providers](https://github.com/apple/swift-log/blob/main/Sources/Logging/Docs.docc/Proposals/SLG-0001-metadata-providers.md)
    - [Introduce task local logger](https://github.com/apple/swift-log/pull/315)
    - [Add withMetadata() convenience function for adding multiple metadata k/v pairs to a Logger](https://github.com/apple/swift-log/pull/322)

### Introduction

A `Logger` parameter is the only ergonomic way today to carry accumulated metadata through internal APIs. This
proposal lets a module declare a task-local logger once and emit through it directly, with scoped metadata
accumulation, without adding a `logger:` parameter to every internal function.

### Motivation

Consider a request handler that wants `request.id` on every log line emitted in the call tree:

```swift
func handleRequest(_ req: Request, logger: Logger) async throws {
    var logger = logger
    logger[metadataKey: "request.id"] = "\(req.id)"
    try await validate(req, logger: logger)
    try await execute(req, logger: logger)
}

func validate(_ req: Request, logger: Logger) async throws { ... }
func execute(_ req: Request, logger: Logger) async throws { ... }
```

Every internal function grows a `logger:` parameter that is noise to its actual job. The alternative —
reconstructing `Logger(label: "my-app", metadata: ...)` at each call site — is verbose and allocates per call.

`TaskLocal<Logger>` from the standard library is the right primitive for this, but its bare API is awkward:

```swift
enum MyApp {
    static let logger: TaskLocal<Logger> = TaskLocal(wrappedValue: Logger(label: "my-app"))
}

// To emit: unwrap explicitly.
MyApp.logger.wrappedValue.info("handling")

// To scope metadata: clone, mutate, rebind.
var copy = MyApp.logger.wrappedValue
copy[metadataKey: "request.id"] = "r1"
MyApp.logger.withValue(copy) {
    MyApp.logger.wrappedValue.info("handling")
}
```

Does the job, but verbose enough that nobody will use it.

### Proposed solution

This proposal adds:

- **`Logger.withMetadata(merging:)`** — value-level instance method that returns a copy of the receiver with
  metadata merged in.
- **Extension on `TaskLocal where Value == Logger`** that adds:
  - **Emit forwarders** for every Logger emit method (`log`, `trace`, `debug`, `info`, `notice`, `warning`,
    `error`, `critical`) — `MyApp.logger.info("...")` calls the bound logger's `info` directly.
  - **`withMetadata(merging:_:)`** — scope-level wrapper that uses `Logger.withMetadata(merging:)` on the bound
    value, then rebinds via `TaskLocal.withValue` for the duration of the operation.

A function that received a logger as a parameter can add context for a block:

```swift
func parseRequest(_ data: Data, logger: Logger) throws -> Request {
    let logger = logger.withMetadata(merging: ["data.size": "\(data.count)"])
    logger.debug("parsing")
    // ...
}
```

A module declares its task-local logger and uses it directly:

```swift
enum MyApp {
    static let logger: TaskLocal<Logger> = TaskLocal(wrappedValue: Logger(label: "my-app"))
}

func handleRequest(_ req: Request) async throws {
    try await MyApp.logger.withMetadata(merging: ["request.id": "\(req.id)"]) {
        MyApp.logger.info("handling")           // label=my-app, request.id=<id>
        try await validate(req)
        try await execute(req)
    }
}

func validate(_ req: Request) async throws {
    MyApp.logger.info("validating")             // sees request.id automatically
}

func execute(_ req: Request) async throws {
    try await DatabaseClient().query(...)       // its own Logger, no metadata leak
}
```

The metadata scope is value-level — `MyApp.logger.withMetadata(...)` only affects `MyApp.logger`. Library code
that constructs its own `Logger(label: "lib")` is unaffected. Other modules that declare their own
`TaskLocal<Logger>` are unaffected.

### Detailed design

```swift
extension Logger {
    /// Returns a copy of this logger with `metadata` merged into its existing metadata.
    /// Keys in `metadata` override existing keys with the same name.
    @inlinable
    public func withMetadata(merging metadata: Logger.Metadata) -> Logger
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension TaskLocal where Value == Logger {
    /// Push `metadata` onto the bound logger for the duration of `operation`. Inside the
    /// closure, the task-local resolves to a copy of the outer logger with `metadata`
    /// merged in. Nested scopes accumulate; inner keys override outer.
    public func withMetadata<Result>(
        merging metadata: Logger.Metadata,
        _ operation: () throws -> Result
    ) rethrows -> Result

    /// Async variant of ``withMetadata(merging:_:)``.
    public func withMetadata<Result>(
        merging metadata: Logger.Metadata,
        _ operation: nonisolated(nonsending) () async throws -> Result
    ) async rethrows -> Result

    // Emit forwarders. For each of `log`, `trace`, `debug`, `info`, `notice`, `warning`,
    // `error`, `critical`, one `@inlinable` overload (with the `error:` parameter)
    // that forwards to the bound logger's corresponding method, preserving
    // `@autoclosure` laziness via expression forwarding:
    @inlinable
    public func info(
        _ message: @autoclosure () -> Logger.Message,
        error: @autoclosure () -> (any Error)? = nil,
        metadata: @autoclosure () -> Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID, function: String = #function, line: UInt = #line
    )

    // …same shape for log/trace/debug/notice/warning/error/critical.
}
```

### API stability

- **No changes** to `Logger`'s public API, `LogHandler`'s requirements, or `LoggingSystem`'s behaviour.
- **Performance.** Every emit via the extension does one task-local `wrappedValue` read in addition to the
  Logger's existing log-level check. Benchmarks under `Benchmarks/NoTraits` cover this overhead. Callers on the
  hottest paths retain the explicit `Logger`-as-parameter pattern from <doc:003-AcceptingLoggers>.
- **Source compatibility.** Additive. Codebases that already use `TaskLocal<Logger>` continue to compile; the new
  methods are reachable through dot syntax.
- **Relationship to SLG-0001 `MetadataProvider`.** Complimentary. `withMetadata(merging:_:)` operates at *bind time*
  (the metadata becomes part of the bound logger's base metadata). A `MetadataProvider` attached to the handler
  runs at *emission time* and is layered per the existing handler-base → provider → per-statement merge order.
  The two compose without interaction: scope metadata sits on the bound logger; provider output is computed and
  merged when the line is emitted.

### Future directions

- **SLG-0007: Scoped logger factory.** Add `withLoggerFactory(_:_:)` to scope the handler factory for a structured
  block — useful for tests, per-subsystem backends, and resolving the static-let trap on user-declared
  `TaskLocal<Logger>`s.
- **SLG-0008: Default `Logger.current`.** Ship a default `TaskLocal<Logger>` named `Logger.current` for callers
  who don't want the per-module declaration boilerplate.
- **`Logger.withMetadata(replacing:)` and the matching `TaskLocal<Logger>.withMetadata(replacing:_:)` scope.**
  A counterpart to `merging:` that replaces the entire metadata dictionary instead of merging on top. Useful at
  request boundaries that want to start with a fresh metadata set, dropping anything inherited from outer scopes.
- **`TaskLocal<Logger>.withLogLevel(_:_:)` scope.** Set a different `logLevel` on the bound logger for a scope.
  Useful for temporarily widening a subsystem to `.debug` for a single block, or narrowing a noisy library to
  `.warning` without touching its handler. Same shape as `withMetadata(merging:_:)` introduced in this proposal.
- **`@Logger` declaration macro.** A purpose-built macro for declaring task-local loggers.

### Alternatives considered

#### A single shared `TaskLocal<Logger>` owned by swift-log instead of user-declared task-locals

Ship one swift-log-owned `TaskLocal<Logger>` as the *only* mechanism. Rejected because it forces the same
task-local logger across every module, so metadata pushed by one module appears on every other module's reads for
the duration of the scope. User-declared `TaskLocal<Logger>`s are structurally isolated by import — `MyApp.logger`
is invisible to `MyDB`. (A swift-log-owned default would still have a place as a convenience for callers who don't
want the per-module declaration; that's left to a follow-up.)
