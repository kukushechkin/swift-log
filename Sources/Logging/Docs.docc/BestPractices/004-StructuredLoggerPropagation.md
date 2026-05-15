# 004: Structured logger propagation with task-locals

Use a per-module `TaskLocal<Logger>` (or the default ``Logger.current``) plus
`withLoggerFactory(_:_:)` to scope a handler factory and accumulate metadata through async
call stacks without adding a `logger:` parameter to every API.

## Guide

SwiftLog ships three pieces that work together:

- **Extension on `TaskLocal<Logger>`** (SLG-0006). Lets any `TaskLocal<Logger>` (yours or
  swift-log's) act as a scoped logger: it forwards Logger's emit methods, and provides
  `withMetadata(merging:_:)` for scope-bound metadata accumulation.
- **`withLoggerFactory(_:_:)`** (SLG-0007). Binds a task-local handler factory consulted
  by ``Logger/init(label:)``. Lets you scope a backend swap to a subsystem, or a test.
- **Default ``Logger.current``** (SLG-0008). A swift-log-owned ``TaskLocal<Logger>`` for
  callers who don't want to declare their own.

### When to use which

- **Per-module declared `TaskLocal<Logger>`** when you want structural isolation: each
  module's accumulated metadata is invisible to other modules.
- **``Logger.current``** when you want the simple ergonomic default and don't need
  per-module isolation.
- **`withLoggerFactory(_:_:)`** when you need to scope which handler (backend) gets
  built — most often in tests, or per-subsystem routing.

### When to keep passing `Logger` explicitly

Task-local propagation is additive; it does not replace accepting a ``Logger`` parameter.
Prefer the explicit parameter pattern described in <doc:003-AcceptingLoggers> when:

- The call site is synchronous and the caller already has a configured logger to pass.
- The function needs the caller's exact logger identity (label, base metadata, log level),
  not a task-local one.
- Your code runs on platforms or toolchains that predate `TaskLocal` availability.
- This is a hot path and task-local storage access critically affects performance.

### Application setup at the entry point

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

`Logger(label:)` calls inside the scope (including library code's own constructions)
route through `StreamLogHandler.standardError`.

### Declaring a per-module scoped logger

```swift
enum MyApp {
    static let logger: TaskLocal<Logger> = TaskLocal(wrappedValue: Logger(label: "my-app"))
}

try await MyApp.logger.withMetadata(merging: ["request.id": "\(req.id)"]) {
    MyApp.logger.info("handling")
}
```

`Logger.init(label:)` runs lazily, on first access — so the captured handler comes from
``LoggingSystem/factory`` (or the scoped factory if one is in effect at first access).

### Using `Logger.current`

When you don't need a per-module identity, ``Logger.current`` works the same way:

```swift
try await Logger.current.withMetadata(merging: ["request.id": "\(req.id)"]) {
    Logger.current.info("handling")
}
```

### Two library patterns

Libraries pick between two patterns depending on how their log lines are best consumed.
Both preserve caller control.

Pattern A — **read a task-local logger**. Suits libraries whose output reads better as
part of the surrounding request context than as a distinct subsystem.

```swift
public struct MetricsHelper {
    public func record(_ event: String) {
        Logger.current.info("metric: \(event)")
    }
}

try await Logger.current.withMetadata(merging: ["request.id": "r1"]) {
    MetricsHelper().record("hit")
}
```

Pattern B — **construct ``Logger/init(label:)``**. Suits libraries with a distinct
subsystem identity worth surfacing (database drivers, HTTP clients, schedulers). Callers
retain control by binding a factory via `withLoggerFactory(_:_:)`.

```swift
public struct DatabaseClient {
    public func query(_ sql: String) {
        Logger(label: "postgres-client").debug("Executing", metadata: ["sql": "\(sql)"])
    }
}

try await withLoggerFactory(StreamLogHandler.standardError) {
    DatabaseClient().query("SELECT …")
}
```

Both patterns are first-class; the choice is editorial, not technical.

## Tips

### Bind `Logger.current` early — and only from application code

``Logger.current`` is initialised lazily on its first access of any kind — *read or
`withValue`* — via `swift_once`. At that moment the default `Logger(label: "")` is
constructed, capturing whichever factory ``LoggingSystem/factory`` returns then. That
factory persists in the default value for the life of the process.

To avoid that capture mattering, **bind `Logger.current` once, as early as possible —
at `@main` before any application code runs:**

```swift
@main
struct MyServer {
    static func main() async throws {
        try await Logger.current.withValue(Logger(label: "my-server")) {
            try await runServer()    // every Logger.current read sees this binding
        }
    }
}
```

The empty-label default is deliberate. An empty-label log line in production output is
the diagnostic signal that nobody bound ``Logger.current`` before that emission — exactly
the failure mode you want to be visible, not a named-but-misleading placeholder you'd
grep right past.

**``Logger.current`` is application API. Reading it from library code is a bug.** Two
co-resident libraries that both read ``Logger.current`` would observe each other's
metadata pushes; a library that reads ``Logger.current`` before the application has
bound it emits with the empty-label default into whatever output the caller has wired up.
Libraries that want a scoped logger declare their own `TaskLocal<Logger>`, or accept a
``Logger`` parameter per <doc:003-AcceptingLoggers>.

### Pinning the handler when `withLoggerFactory` is in effect

To pin ``Logger.current``'s handler to a scoped factory, rebind explicitly inside
`withLoggerFactory(_:_:)`:

```swift
try await withLoggerFactory(myFactory) {
    try await Logger.current.withValue(Logger(label: "")) {  // freshly built with myFactory
        try await runWork()
    }
}
```

The `Logger(label: "")` argument is evaluated *inside* the enclosing `withLoggerFactory`
scope — that's what makes it pick up the scoped factory. (Were the same expression
hoisted to a `let` outside the block, it would capture the surrounding factory, not the
scoped one.)

The same `withValue` rebuild applies to user-declared `TaskLocal<Logger>`s, not just
``Logger.current``. A per-module logger declared as a static let has the same static-let
trap — its handler comes from whichever factory was current when the static let first
initialised. To use it with a scoped factory, rebuild the same way:

```swift
try await withLoggerFactory(testHandler) {
    try await MyApp.logger.withValue(Logger(label: "my-app")) {
        try await runFeature()  // MyApp.logger's handler comes from testHandler
    }
}
```

### Sharing accumulated metadata with library loggers (opt-in)

By default, ``Logger/init(label:)`` does not merge any task-local metadata. Library
loggers carry only their own label and per-statement metadata — no accumulated metadata
leaks. To explicitly opt into sharing accumulated metadata with library loggers, wrap
the factory:

```swift
try await withLoggerFactory({ label, provider in
    var handler = StreamLogHandler.standardError(label: label, metadataProvider: provider)
    // Bake an application-owned metadata snapshot into every handler in scope.
    handler.metadata = MyApp.logger.wrappedValue.handler.metadata
    return handler
}) {
    try await MyApp.logger.withMetadata(merging: ["request.id": "r1"]) {
        DatabaseClient().query("SELECT …")  // postgres-client's handler now has request.id
    }
}
```

The opt-in lives in the factory, so the default remains the isolated one.

### Bridging a custom `TaskLocal<Logger>` to `Logger.current`

Libraries that follow Pattern A read ``Logger.current``. If the application binds its
own ``TaskLocal<Logger>`` instead — or carries an accumulated logger that isn't a
task-local at all — those libraries see ``Logger.current``'s default, not the
application's current logger. Bridge by mirroring the bound value into
``Logger.current`` for the scope:

```swift
enum MyApp {
    static let logger: TaskLocal<Logger> = TaskLocal(wrappedValue: Logger(label: "my-app"))
}

public struct MetricsHelper {
    public func record(_ event: String) {
        Logger.current.info("metric: \(event)")    // Pattern A
    }
}

try await MyApp.logger.withMetadata(merging: ["request.id": "r1"]) {
    try await Logger.current.withValue(MyApp.logger.wrappedValue) {
        MetricsHelper().record("hit")    // sees request.id=r1
    }
}
```

`MyApp.logger.wrappedValue` resolves to the current bound `Logger` — including any
metadata pushed by enclosing `withMetadata(merging:_:)` scopes — and
`Logger.current.withValue` adopts that value for the inner closure. The same one-liner
bridges any non-task-local source: `Logger.current.withValue(myConfiguredLogger) { … }`.

The reverse direction needs no bridge — application code that reads ``Logger.current``
sees whatever the application has bound there, regardless of whether a custom
task-local is also in use.

### Caching a library logger vs. constructing per call

A library that follows Pattern B has two reasonable caching strategies.
``Logger/init(label:)`` reads the task-local factory at construction time, so *when*
construction runs determines which backend the cached handler uses.

**Cache at construction time** (common case):

```swift
public struct MyLib {
    private let logger: Logger

    public init() {
        self.logger = Logger(label: "my-lib")  // captures factory at init-time scope
    }

    public func doWork() {
        self.logger.info("working")
    }
}
```

Use this when the library is constructed at a predictable point — typically startup,
before any `withLoggerFactory(_:_:)` scope is entered, or explicitly within a known scope.

**Construct per call** (when the library must follow scoped factory changes):

```swift
public struct MyLib {
    public func doWork() {
        Logger(label: "my-lib").info("working")  // picks up the current scope's factory
    }
}
```

Use this when the library needs to follow the caller's current `withLoggerFactory(_:_:)`
scope on every call.

### Avoid: file-scope `private let` or `static let` loggers

Swift initialises a file-scope `let` or a type-level `static let` lazily, once per
process, on the first access — guarded by `swift_once`. The thread that triggers the
first access does so *inside its current task-local scope*, and the factory captured at
that moment persists for the life of the process.

```swift
// ❌ Avoid — first caller to touch `logger` determines its init scope.
private let logger = Logger(label: "my-lib")
```

Prefer an instance `let` property (cache at construction) or per-call construction.

The same `swift_once` trap applies to a user-declared `TaskLocal<Logger>` and to the
default ``Logger.current`` — first access fixes the captured factory in the default
value. To pin a specific factory, rebind explicitly inside the scope (`local.withValue(...)`).

### Structured concurrency semantics

Both task-locals (yours and ``Logger.current``) inherit Swift's `TaskLocal` behaviour
unchanged:

- `async let`, `withTaskGroup`, and unstructured `Task { }` children **inherit** scopes.
- For unstructured `Task { ... }`, the binding list is **snapshotted at task creation**.
  Bindings popped in the parent before the child reads them are still visible to the
  child; bindings pushed in the parent after the child starts are *not* visible. If the
  child needs the parent's most-recent binding, hand it across explicitly rather than
  relying on the snapshot.
- `Task.detached` **does not** inherit scopes. If you spawn detached work that must log
  under the caller's context, capture the required values explicitly and rebind them at
  the top of the detached task.
