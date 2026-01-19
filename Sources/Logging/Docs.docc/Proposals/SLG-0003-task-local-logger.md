# SLG-0003: Task-local logger with automatic metadata propagation

Accumulate structured logging metadata across async call stacks using task-local storage.

## Overview

- Proposal: SLG-0003
- Author(s): [Author Name](https://github.com/author)
- Status: **Awaiting Review**
- Issue: [apple/swift-log#XXX](https://github.com/apple/swift-log/issues/XXX)
- Implementation: [apple/swift-log#XXX](https://github.com/apple/swift-log/pull/XXX)

### Introduction

Add task-local logger storage to enable progressive metadata accumulation without explicit logger parameters. This proposal focuses on solving metadata propagation challenges in applications and libraries.

### Motivation

Modern Swift applications face two primary challenges when trying to maintain rich, contextual logging with accumulated metadata.

#### Problem 1: Metadata propagation throughout the application flow

Applications need to accumulate structured metadata as execution flows through layers:

```swift
// Layer 1: HTTP handler adds request context
func handleHTTPRequest(_ request: HTTPRequest, logger: Logger) async throws {
    var logger = logger
    logger[metadataKey: "request.id"] = "\(request.id)"
    try await processBusinessLogic(request, logger: logger)
}

// Layer 2: Business logic adds user context
func processBusinessLogic(_ request: HTTPRequest, logger: Logger) async throws {
    let user = try await authenticate(request, logger: logger)
    var logger = logger
    logger[metadataKey: "user.id"] = "\(user.id)"
    try await accessDatabase(user, logger: logger)
}

// Layer 3: Database layer wants request.id, user.id, AND table context
func accessDatabase(_ user: User, logger: Logger) async throws {
    var logger = logger
    logger[metadataKey: "table"] = "users"
    logger.info("Query")
}
```

Every layer must accept a logger parameter, mutate it to add metadata, and pass it to the next layer. This is verbose and error-prone.

#### Problem 2: Library APIs polluted by logging and lost metadata context

Libraries face a dilemma with three unsatisfying options:

**Option A: Pollute public APIs**

```swift
public struct DatabaseClient {
    public func query(_ sql: String, logger: Logger) async throws -> [Row] {
        var logger = logger
        logger[metadataKey: "sql"] = "\(sql)"
        logger.debug("Query")
        return try await performQuery(sql, logger: logger)
    }

    private func performQuery(_ sql: String, logger: Logger) async throws -> [Row] {
        var logger = logger
        logger[metadataKey: "step"] = "validation"
        try await checkFraudRules(logger: logger)
    }
}
```

**Option B: Create ad-hoc loggers and lose context**

```swift
public struct DatabaseClient {
    public func query(_ sql: String) async throws -> [Row] {
        let logger = Logger(label: "database")
        logger.debug("Query", metadata: ["sql": "\(sql)"])
        // Lost: request.id, user.id, trace.id, etc.
        return try await performQuery(sql)
    }
}
```

**Option C: Don't log at all**

```swift
public struct DatabaseClient {
    public func query(_ sql: String) async throws -> [Row] {
        // No observability into library behavior
        return try await performQuery(sql)
    }
}
```

### Proposed solution

Use Swift's `@TaskLocal` storage to automatically propagate logger with accumulated metadata:

```swift
// Application code - no logger parameters needed
func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
    try await Logger.with(additionalMetadata: ["request.id": "\(request.id)"]) { logger in
        logger.info("Handling request")
        let user = try await authenticate(request)  // No logger parameter
        return try await processRequest(request, user: user)
    }
}

func authenticate(_ request: HTTPRequest) async throws -> User {
    Logger.current.debug("Authenticating")  // Has request.id automatically!
}
```

**Library code - clean APIs, full context:**

```swift
public struct DatabaseClient {
    // Public API has no logger parameter
    public func query(_ sql: String) async throws -> [Row] {
        // Logs with ALL accumulated parent metadata (request.id, user.id, etc.)
        Logger.current.debug("Query", metadata: ["sql": "\(sql)"])
        return try await performQuery(sql)
    }

    private func performQuery(_ sql: String) async throws -> [Row] {
        // Internal functions also have full context
        Logger.current.trace("Opening connection")
        // ...
    }
}
```

**Progressive metadata accumulation:**

```swift
Logger.with(additionalMetadata: ["request.id": "\(request.id)"]) { _ in
    // All code here has request.id

    Logger.with(additionalMetadata: ["user.id": "\(user.id)"]) { _ in
        // All code here has BOTH request.id AND user.id

        Logger.with(additionalMetadata: ["operation": "payment"]) { _ in
            // All code here has request.id, user.id, AND operation
            Logger.current.info("Processing")  // All metadata automatically included
        }
    }
}
```

Child tasks inherit parent context automatically through Swift's structured concurrency.

### Detailed design

**Public APIs:**

```swift
// Static methods - modify task-local context
extension Logger {
    // Access current task-local logger
    public static var current: Logger { get }

    public static func withCurrent<R>(_ body: (Logger) -> R) -> R

    public static func withCurrent<R>(_ body: (Logger) async -> R) async -> R

    // Initial task-local logger setup
    public static func with<R>(
        label: String,
        handler: LogHandler,
        logLevel: Logger.Level,
        _ body: (Logger) throws -> R
    ) rethrows -> R

    public static func with<R>(
        label: String,
        handler: LogHandler,
        logLevel: Logger.Level,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R

    // Metadata modification
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        _ body: (Logger) throws -> R
    ) rethrows -> R

    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R
}

// Instance methods - create modified loggers
extension Logger {
    public func with(additionalMetadata: Logger.Metadata) -> Logger
}
```

### Performance considerations

Task-local storage access has runtime overhead compared to explicit parameter passing:

1. **`Logger.current`** - Performs task-local lookup on each access.
2. **`Logger.withCurrent { logger in }`** - Single lookup with closure-captured logger.

**When to use each?**

- Use `Logger.current` for occasional logging where convenience matters most.
- Use `Logger.withCurrent { }` in performance-sensitive code with many log calls.
- Use explicit parameter passing in tight loops if profiling identifies task-local access as a bottleneck.

In tight loops with many log calls, `Logger.current` overhead accumulates. `Logger.withCurrent { }` performs the lookup once and captures the logger, making repeated accesses more efficient.

### API stability

Purely additive. No changes to existing `Logger` users or `LogHandler` implementations. Users must adopt the new task-local APIs to benefit. Existing ad-hoc loggers will keep losing parent metadata.

### Future directions

- Add `.with(handler:)`, `.with(logLevel:)` and their combinations to allow full control over the TaskLocal logger instance.

### Alternatives considered

#### Task-local metadata dictionary instead of task-local logger

An alternative approach would make only the metadata dictionary task-local:

```swift
// Hypothetical alternative API
Logger.withTaskLocalMetadata(["request.id": "\(request.id)"]) {
    // All Logger instances automatically merge task-local metadata
    let logger = Logger(label: "database")  // Ad-hoc logger now gets parent metadata!
    logger.info("Query")  // Has request.id from task-local storage
}
```

This would allow ad-hoc logger creation while preserving parent metadata.

**Why this was rejected:**

1. **Semantically confusing**: Decouples logger from its metadata. `Logger(label: "foo")` would have different metadata depending on whether it's inside a task-local scope, making logger metadata unpredictable.

2. **Changes default behavior**: All existing logger creation suddenly merges invisible metadata, which is a breaking semantic change affecting all code.

3. **Overlaps with swift-distributed-tracing**: Swift's distributed tracing already provides task-local propagation for tracing contexts. Having two competing task-local metadata systems creates confusion about which to use.

The proposed solution is more explicit: library authors consciously adopt `Logger.current`, making the behavior clear and intentional.

#### Public `taskLocalLogger` property

Rejected—exposes implementation detail, more verbose.
