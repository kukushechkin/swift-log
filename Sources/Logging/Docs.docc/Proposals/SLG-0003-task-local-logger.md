# SLG-0003: Task-local logger context propagation

Propagate logger context automatically through Swift structured concurrency without explicit parameters.

## Overview

- Proposal: SLG-0003
- Author(s): [Author Name](https://github.com/author)
- Status: **Awaiting Review**
- Issue: [apple/swift-log#XXX](https://github.com/apple/swift-log/issues/XXX)
- Implementation: [apple/swift-log#XXX](https://github.com/apple/swift-log/pull/XXX)

### Introduction

Add task-local logger storage to propagate context through async call stacks without explicit parameter passing.

### Motivation

Async applications require threading loggers through every function to accumulate structured metadata:

```swift
func handleRequest(_ request: HTTPRequest, logger: Logger) async throws -> HTTPResponse {
    let logger = logger.with(additionalMetadata: ["request.id": "\(request.id)"])
    logger.info("Handling request")
    let user = try await authenticate(request, logger: logger)
    return try await processRequest(request, user: user, logger: logger)
}

func authenticate(_ request: HTTPRequest, logger: Logger) async throws -> User {
    let logger = logger.with(additionalMetadata: ["auth.method": "token"])
    logger.debug("Authenticating")
}
```

This pollutes APIs and complicates progressive metadata accumulation. A typical HTTP request flows through 15-20 functions—all need logger parameters to preserve context.

**Alternative: Ad-hoc logger creation** is equally problematic:

```swift
func authenticate(_ request: HTTPRequest) async throws -> User {
    let logger = Logger(label: "auth")  // Uses LoggingSystem.bootstrap factory
    logger.debug("Authenticating")  // Lost all request context!
}
```

This couples code to global `LoggingSystem.bootstrap()` state, making tests interfere when running concurrently. Each test must either bootstrap differently (global mutation) or accept the globally configured handler. Worse, it loses accumulated metadata from the calling context.

### Proposed solution

Use Swift's `@TaskLocal` for implicit propagation:

```swift
func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
    try await Logger.with(additionalMetadata: ["request.id": "\(request.id)"]) { logger in
        logger.info("Handling request")
        let user = try await authenticate(request)  // No logger parameter
        return try await processRequest(request, user: user)
    }
}

func authenticate(_ request: HTTPRequest) async throws -> User {
    Logger.withExistingContext { logger in
        logger.debug("Authenticating")  // Has request.id!
    }
}
```

Child tasks inherit parent context automatically. Libraries can log without logger parameters.

### Detailed design

**Public APIs:**

```swift
// Static methods - modify task-local context
@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension Logger {
    // Single-parameter modifications
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        _ body: (Logger) throws -> R
    ) rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        logLevel: Logger.Level,
        _ body: (Logger) throws -> R
    ) rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        logLevel: Logger.Level,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        handler: any LogHandler,
        _ body: (Logger) throws -> R
    ) rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        handler: any LogHandler,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R

    // Combined parameter modifications
    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        _ body: (Logger) throws -> R
    ) rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        handler: any LogHandler,
        _ body: (Logger) throws -> R
    ) rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        handler: any LogHandler,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) throws -> R
    ) rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) throws -> R
    ) rethrows -> R

    @discardableResult
    @inlinable
    public static func with<R>(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) async throws -> R
    ) async rethrows -> R

    // Access existing context
    @discardableResult
    @inlinable
    public static func withExistingContext<R>(_ body: (Logger) -> R) -> R

    @discardableResult
    @inlinable
    public static func withExistingContext<R>(_ body: (Logger) async -> R) async -> R
}

// Instance methods - create modified loggers
extension Logger {
    @inlinable
    public func with(additionalMetadata: Logger.Metadata) -> Logger

    @inlinable
    public func with(logLevel: Logger.Level) -> Logger

    @inlinable
    public func with(handler: any LogHandler) -> Logger

    @inlinable
    public func with(additionalMetadata: Logger.Metadata, logLevel: Logger.Level) -> Logger

    @inlinable
    public func with(additionalMetadata: Logger.Metadata, handler: any LogHandler) -> Logger

    @inlinable
    public func with(logLevel: Logger.Level, handler: any LogHandler) -> Logger

    @inlinable
    public func with(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        handler: any LogHandler
    ) -> Logger
}
```

**Implementation notes:**

All methods are `@inlinable` for zero-cost abstraction. Internal storage uses `@TaskLocal` with `SwiftLogNoOpLogHandler` default (decoupled from `LoggingSystem.bootstrap()`).

Instance `with()` methods optimize for single-key metadata and use `reserveCapacity()` for multi-key merges. Named `with()` not `copy()` to follow Swift functional conventions (see `Optional.map`, `Result.map`).

### API stability

Purely additive. No changes to existing `Logger` users or `LogHandler` implementations. All APIs are `@inlinable` (no ABI impact).

### Future directions

- Integration with distributed tracing (trace/span ID propagation)
- Combine with `MetadataProvider` (SLG-0001) for automatic context injection

### Alternatives considered

**Public `taskLocalLogger` property:** Rejected—exposes implementation detail, allows misuse.

**Use `LoggingSystem.factory` as default:** Rejected—couples task-local to global bootstrap.

**Builder pattern:** Rejected—adds complexity, harder to inline, verbose for common case.

**Named `copy()` not `with()`:** Rejected—violates Swift API guidelines, no stdlib precedent.

## Usage Examples

**Progressive context accumulation:**
```swift
func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
    try await Logger.with(additionalMetadata: ["request.id": "\(request.id)"]) { logger in
        logger.info("Request received")
        let user = try await authenticate(request)

        return try await Logger.with(additionalMetadata: ["user.id": "\(user.id)"]) { logger in
            logger.info("User authenticated")
            return try await processRequest(request, user)
        }
    }
}

func processRequest(_ request: HTTPRequest, user: User) async throws -> HTTPResponse {
    Logger.withExistingContext { logger in
        logger.debug("Processing")  // Has request.id AND user.id
    }
}
```

**Library logging without coupling:**
```swift
public struct DatabaseClient {
    public func query(_ sql: String) async throws -> [Row] {
        Logger.withExistingContext { logger in
            logger.debug("Query", metadata: ["sql": "\(sql)"])
        }
        return try await performQuery(sql)
    }
}
```

**Testing:**
```swift
@Test func test() async throws {
    let testLogger = Logger(label: "test") { TestHandler() }
    await Logger.with(handler: testLogger.handler) {
        await handleRequest(mockRequest)
    }
}
```
