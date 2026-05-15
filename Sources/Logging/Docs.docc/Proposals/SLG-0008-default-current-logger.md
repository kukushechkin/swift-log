# SLG-0008: Default `Logger.current`

Ship a default `TaskLocal<Logger>` named `Logger.current` so callers who don't want to declare their own per-module
task-local logger can call `Logger.current.info(...)` directly.

## Overview

- Proposal: SLG-0008
- Author(s): [Vladimir Kukushkin](https://github.com/kukushechkin)
- Status: **Awaiting Review**
- Issue: [apple/swift-log#261](https://github.com/apple/swift-log/issues/261)
- Implementation: [apple/swift-log#XXX](https://github.com/apple/swift-log/pull/XXX)
- Feature flag: none
- Related links:
    - [Lightweight proposals process description](https://github.com/apple/swift-log/blob/main/Sources/Logging/Docs.docc/Proposals/Proposals.md)
    - [SLG-0006: Task-local Logger extensions](SLG-0006-task-local-logger.md)
    - [SLG-0007: Scoped logger factory](SLG-0007-scoped-logger-factory.md)
    - [Introduce task local logger](https://github.com/apple/swift-log/pull/315)

### Introduction

SLG-0006 establishes `TaskLocal<Logger>` as the building block for scoped per-module loggers. This proposal adds a
single `TaskLocal<Logger>` instance shipped by swift-log itself — `Logger.current` — for callers who don't want to
declare their own.

### Motivation

Under <doc:SLG-0006-task-local-logger>, every module that wants a scoped logger writes the same boilerplate:

```swift
enum MyApp {
    static let logger: TaskLocal<Logger> = TaskLocal(wrappedValue: Logger(label: "my-app"))
}
```

For multi-module applications where each module owns its own concern that's appropriate — structural isolation
between modules is exactly the point. But for ad-hoc scripts and simple applications it's three lines of ceremony
with no corresponding benefit.

### Proposed solution

Add a public `TaskLocal<Logger>` to `Logger` named `current`, with an empty-labelled default. Inside a scope (bound
via `withValue` or one of <doc:SLG-0006-task-local-logger>'s extension methods), it resolves to whatever the caller
bound.

```swift
extension Logger {
    public static let current: TaskLocal<Logger> = TaskLocal(wrappedValue: Logger(label: ""))
}
```

Use it directly without per-module declaration:

```swift
@main
struct MyServer {
    static func main() async throws {
        try await Logger.current.withMetadata(merging: ["service": "my-server"]) {
            try await runServer()
        }
    }
}

func handleRequest(_ req: Request) async throws {
    try await Logger.current.withMetadata(merging: ["request.id": "\(req.id)"]) {
        Logger.current.info("handling")  // service=my-server, request.id=<id>
    }
}
```

`Logger.current` is *additive* to <doc:SLG-0006-task-local-logger> — both patterns coexist. A project can use
`Logger.current` in some places and per-module `TaskLocal<Logger>`s in others, depending on whether structural
isolation matters.

Everything else — emit forwarders, metadata-scope, structured-concurrency propagation — comes from
<doc:SLG-0006-task-local-logger>'s extension on `TaskLocal where Value == Logger`. This proposal contributes one
declaration.

### Detailed design

```swift
extension Logger {
    /// A default global ``TaskLocal`` logger. Use directly with the SLG-0006 extension
    /// surface for ergonomic scoped logging without declaring a per-module task-local.
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    public static let current: TaskLocal<Logger>
}
```

`Logger.current` is application API: ``LoggingSystem/factory``-captured at first access via `swift_once`. The
recommended bind-early-at-`@main` pattern, the empty-label-as-diagnostic rationale, and the rebuild idiom for
composing with `withLoggerFactory(_:_:)` are documented in <doc:004-StructuredLoggerPropagation>.

### API stability

- **No changes** to `Logger.init(label:)`, `LogHandler`, or `LoggingSystem`.
- **Performance.** No additional cost beyond what SLG-0006 already documents.
- **Source compatibility.** `Logger.current` is a new public name on `Logger`. Codebases that declare a static
  `current` member on `Logger` via extension would collide; workaround: rename or fully qualify.

### Future directions

- **Customisable default label.** Let the application override the empty-label default at startup —
  e.g., `LoggingSystem.bootstrapCurrent(label: "my-app")` — so unbound reads of `Logger.current` render with a
  meaningful label. Deferred until we see whether the empty-label rendering is a problem in practice.

### Alternatives considered

#### Make `Logger.current` a computed `Logger` (auto-unwrapped)

Expose `Logger.current` as a property that returns a `Logger` directly, hiding the task-local. Rejected because
SLG-0006's extension surface is defined on `TaskLocal<Logger>`. A `Logger`-typed `current` would need a parallel
set of swift-log-owned helpers (`withLoggerMetadata(merging:_:)` free function, etc.) — duplicating SLG-0006's
surface for the default case alone. Keeping `Logger.current` as a `TaskLocal<Logger>` lets it share the same
machinery as user-declared task-locals.

#### Default to a placeholder label like `"swift-log.current"`

Use a non-empty default label to make it obvious in log output when nobody has bound `Logger.current`. Rejected
because non-empty placeholders show up in production output as a real subsystem name, which is misleading and
easy to grep right past. The empty label is the deliberate diagnostic signal: any line carrying it is one that
was emitted before the application bound `Logger.current`, which is the failure mode the bind-early guidance is
designed to prevent.
