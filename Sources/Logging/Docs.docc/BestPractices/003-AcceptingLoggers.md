# 003: Accepting loggers in libraries

Accept loggers through method parameters to ensure proper metadata propagation.

## Overview

Libraries should accept logger instances through method parameters rather than
storing them as instance variables. This practice ensures metadata (such as
correlation IDs) is properly propagated down the call stack, while giving
applications control over logging configuration.

### Motivation

When libraries accept loggers as method parameters, they enable automatic
propagation of contextual metadata attached to the logger instance. This is
especially important for distributed systems where correlation IDs must flow
through the entire request processing pipeline.

### Example

#### Recommended: Accept logger through method parameters

```swift
// ✅ Good: Pass the logger through method parameters.
struct RequestProcessor {
    func processRequest(_ request: HTTPRequest, logger: Logger) async throws -> HTTPResponse {
        // Add structured metadata that every log statement should contain.
        var logger = logger
        logger[metadataKey: "request.method"] = "\(request.method)"
        logger[metadataKey: "request.path"] = "\(request.path)"
        logger[metadataKey: "request.id"] = "\(request.id)"

        logger.debug("Processing request")
        
        // Pass the logger down to maintain metadata context.
        let validatedData = try validateRequest(request, logger: logger)
        let result = try await executeBusinessLogic(validatedData, logger: logger)
        
        logger.debug("Request processed successfully")
        return result
    }
    
    private func validateRequest(_ request: HTTPRequest, logger: Logger) throws -> ValidatedRequest {
        logger.debug("Validating request parameters")
        // Include validation logic that uses the same logger context.
        return ValidatedRequest(request)
    }
    
    private func executeBusinessLogic(_ data: ValidatedRequest, logger: Logger) async throws -> HTTPResponse {
        logger.debug("Executing business logic")
        
        // Further propagate the logger to other services.
        let dbResult = try await databaseService.query(data.query, logger: logger)
        
        logger.debug("Business logic completed")
        return HTTPResponse(data: dbResult)
    }
}
```

#### Alternative: Accept logger through initializer when appropriate

```swift
// ✅ Acceptable: Logger through initializer for long-lived components
final class BackgroundJobProcessor {
    private let logger: Logger
    
    init(logger: Logger) {
        self.logger = logger
    }
    
    func run() async {
        // Execute some long running work
        logger.debug("Update about long running work")
        // Execute some more long running work
    }
}
```

#### Alternative: Task-local propagation for intra-module code

In narrow cases — library code that logs from many internal helper functions, where threading a `Logger` through
every internal signature adds noise without new information — the task-local mechanisms from
<doc:004-StructuredLoggerPropagation> offer an alternative that does not require a parameter on every call. Prefer
parameter-passing unless the intra-module noise is a real cost:

- A per-module **`TaskLocal<Logger>`** (or the default ``Logger/current``) reads as a Logger via SLG-0006's
  extension forwarders. Internal helper functions read it without accepting a `logger:` parameter, and metadata
  accumulates via `withMetadata(merging:_:)`.
- **``Logger/init(label:)``** inside a caller's `withLoggerFactory(_:_:)` scope picks up the caller's chosen
  backend while keeping the library's own label. It does not merge any task-local metadata — a freshly-constructed
  logger is isolated from the caller's per-request metadata.

```swift
// Library declares its own identity; no logger: parameter required.
public struct MyLibrary {
    public func operation() {
        Logger(label: "MyLibrary").info("Doing work")
    }
}

// Application scopes the backend once.
try await withLoggerFactory(StreamLogHandler.standardError) {
    try await Logger.current.withMetadata(merging: ["request.id": "r1"]) {
        MyLibrary().operation()
        // Logs with label "MyLibrary", handler from StreamLogHandler.standardError,
        // no request.id — the library's logger is its own.
    }
}
```

If the caller wants `request.id` to reach the library's log lines too, the caller wraps the factory to bake the
accumulated metadata into each handler at construction time; see <doc:004-StructuredLoggerPropagation> for the
factory-wrap pattern.

This is a valid alternative to parameter-passing when a library prefers to own its logging identity and the
caller uses `withLoggerFactory(_:_:)` to scope the backend. It is not a replacement — parameter-passing remains
the recommended pattern when the caller already has a logger and the library only needs one.

Consult <doc:004-StructuredLoggerPropagation> for the cached-vs-per-call trade-off that applies when a library
caches a ``Logger`` as a property: a cached logger captures the factory active at *construction*, so caching and
per-scope backend swaps are in tension.

#### Avoid: `static let` or file-scope `private let` cached loggers under task-local propagation

`Logger`s cached as `static let` on a type or as `private let` at file scope are lazily initialized by Swift
exactly once per process, on the first access — *inside whichever task-local scope that first access happens to
be in*. The factory captured at that moment persists for the life of the process, so the library's log lines
route through whichever backend happened to be in scope when the first caller touched the cached logger.

If your library uses this pattern and your callers use `withLoggerFactory(_:_:)`, prefer an instance-level
`private let logger` constructed at a predictable time, a computed `static var logger: Logger { Logger(label: "…") }`,
or per-call construction. See <doc:004-StructuredLoggerPropagation> for the full matrix.

```swift
// Library accepts logger from caller — always correct, most explicit.
final class MyLibrary {
    func operation(logger: Logger) {
        // Maintains caller's context and metadata.
    }
}

// Library constructs its own logger per call — picks up the caller's current factory.
public struct MyLibrary {
    public func operation() {
        let logger = Logger(label: "MyLibrary")  // Inherits scope factory, own label, no scope metadata.
        logger.info("Doing work")
    }
}
```

