# 004: Task-local logger context

Use task-local loggers to propagate logging context through async boundaries without explicit parameter passing.

## Overview

Task-local loggers attach logging context to the current Swift concurrency task, making it available throughout the async
call stack. This combines automatic context propagation with Swift's structured concurrency guarantees, enabling cleaner
code in server applications, middleware, and library implementations.

The task-local logger API provides:

- **Static `Logger.with()` methods** to set or modify the task-local logger context.
- **`Logger.withExistingContext()`** to access the current task-local logger (cheap: just TaskLocal property access).
- **Instance `.copy()` methods** to create modified logger instances without mutation.

## Use-case: Request-scoped logging in server applications

Set logging context once at request entry points, automatically available throughout request processing.

```swift
// Set context at HTTP request entry point
func handleHTTPRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
    try await Logger.with(
        additionalMetadata: [
            "request.id": "\(request.id)",
            "request.method": "\(request.method)",
            "request.path": "\(request.path)"
        ]
    ) { logger in
        logger.info("Handling request")
        // Child tasks will inherit the metadata from this context
        let result = try await processRequest(request)
        logger.info("Request completed")
        return result
    }
}

// Deep in call stack - context automatically available
func performBusinessLogic(_ data: Data) async throws {
    Logger.withExistingContext { logger in
        logger.debug("Processing business logic")  // Includes request.id, method, path

    // All nested calls have access to the same context
        try await validateData(data)
    }
}
```

**Best practice**: Set context once at entry points, access throughout the call stack without parameter threading.

**Anti-pattern**: Setting context multiple times at the same level instead of accumulating it progressively.

## Use-case: Incremental context enrichment

Add context progressively as requests flow through authentication, authorization, and processing stages.

```swift
func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
    return try await Logger.with(additionalMetadata: ["request.id": "\(request.id)"]) { logger in
        logger.info("Request received")

        let user = try await authenticateUser(request)

        // Add user context for subsequent operations
        return try await Logger.with(additionalMetadata: ["user.id": "\(user.id)"]) { logger in
            try await processAuthenticatedRequest(request, user: user)
        }
    }
}

func processAuthenticatedRequest(_ request: HTTPRequest, user: User) async throws -> HTTPResponse {
    Logger.withExistingContext { logger in
        logger.info("Processing authenticated request")  // Includes request.id AND user.id
        return try await performUserOperation(user)
    }
}
```

**Best practice**: Use nested `Logger.with()` calls to accumulate context as it becomes available.

**Anti-pattern**: Creating new loggers at each stage, losing accumulated context from previous stages.

## Use-case: Library code without explicit logger parameters

Libraries can log using task-local context without requiring explicit logger parameters, reducing API surface.

```swift
// Library code - no logger parameter needed
public struct DatabaseClient {
    public func query(_ sql: String) async throws -> [Row] {
        Logger.withExistingContext { logger in
            logger.debug("Executing query", metadata: ["sql": "\(sql)"])
            let results = try await executeQuery(sql)
            logger.debug("Query completed", metadata: ["rowCount": "\(results.count)"])
            return results
        }
    }
}

// Application sets context once
func handleRequest() async throws {
    try await Logger.with(additionalMetadata: ["request.id": "123"]) { logger in
        let db = DatabaseClient()
        let rows = try await db.query("SELECT * FROM users")  // Logs include request.id
    }
}
```

**Best practice**: Libraries use `withExistingContext()` for optional logging without API coupling to logger types.

**Anti-pattern**: Requiring explicit logger parameters in library APIs when task-local context suffices.

## Use-case: Performance-critical paths

Extract logger once before tight loops to avoid repeated TaskLocal property access overhead.

```swift
func processLargeDataset(_ items: [Item]) async {
    Logger.withExistingContext { logger in
        logger.info("Starting batch processing")

        // Extract once for hot path
        for item in items {
            processItem(item, logger: logger)  // Pass explicitly to avoid TaskLocal overhead
        }

        logger.info("Batch processing completed")
    }
}

func processItem(_ item: Item, logger: Logger) {
    logger.trace("Processing item", metadata: ["item.id": "\(item.id)"])
}
```

**Best practice**: Extract logger once before performance-critical loops, pass explicitly within the loop.

**Anti-pattern**: Calling `withExistingContext()` inside tight loops (unnecessary TaskLocal access overhead).

## Use-case: In-memory logger for testing and state observation

Create task-local in-memory logger for testing, then extract logs for assertions or analysis.

```swift
// Create in-memory test logger
struct InMemoryLogger {
    private let recorder = LogRecorder()

    func makeHandler(label: String) -> LogHandler {
        InMemoryLogHandler(label: label, recorder: recorder)
    }

    var logs: [LogEntry] { recorder.entries }
}

// Use in tests
func testRequestHandling() async {
    let logging = InMemoryLogger()
    let logger = Logger(label: "test", factory: { logging.makeHandler(label: $0) })

    // Set as task-local context
    await Logger.with(handler: logger.handler) { _ in
        // Run code that uses task-local logging
        await Logger.with(additionalMetadata: ["request.id": "123"]) { _ in
            await handleRequest()
        }

        // Extract and verify logs
        let logs = logging.logs
        assert(logs.contains { $0.message == "Request received" && $0.metadata["request.id"] == "123" })
    }
}
```

**Best practice**: Use in-memory loggers with task-local context for testing without global state modification.

**Anti-pattern**: Modifying global `LoggingSystem` state in concurrent tests (causes test interference).

## Use-case: Mixed explicit and implicit propagation

Combine explicit logger parameters for hot paths with implicit context for deep call stacks.

```swift
func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
    let logger = Logger(label: "server")
    let requestLogger = logger.copy(with: ["request.id": "\(request.id)"])

    return try await Logger.with(handler: requestLogger.handler) { logger in
        logger.info("Request received")

        // Performance-critical validation - use explicit logger
        let validated = try validateRequest(request, logger: logger)

        // Deep call stack - use implicit context
        let result = try await processValidatedRequest(validated)

        logger.info("Request completed")

        return result
    }
}

func validateRequest(_ request: HTTPRequest, logger: Logger) throws -> ValidatedRequest {
    logger.debug("Validating request")  // Explicit parameter for hot path
    return ValidatedRequest(request)
}

func processValidatedRequest(_ request: ValidatedRequest) async throws -> HTTPResponse {
    Logger.withExistingContext { logger in
        logger.debug("Processing validated request")  // Implicit for deep call stack
        return try await performBusinessLogic(request)
    }
}
```

**Best practice**: Use explicit parameters for performance-critical paths, implicit context for convenience elsewhere.

**Anti-pattern**: Choosing one approach exclusively when mixing provides better clarity and performance.

## Best practices summary

1. **Set context at entry points**: Use `Logger.with()` once at request or operation boundaries.
2. **Accumulate progressively**: Nest `Logger.with()` calls to add context as it becomes available.
3. **Extract for hot paths**: Call `withExistingContext()` once before loops, pass logger explicitly inside.
4. **Prefer implicit in libraries**: Use task-local context to avoid coupling library APIs to logger types.
5. **Test with in-memory loggers**: Use task-local in-memory loggers for testing without global state.

## Anti-patterns summary

1. **TaskLocal access in tight loops**: Extract logger once before the loop.
2. **Nested `withExistingContext()` calls**: Access once, use logger variable for subsequent calls.
3. **Replacing all explicit loggers**: Simple functions benefit from explicit parameters.
4. **Ignoring provided logger**: When `Logger.with()` provides a logger parameter, use it directly.
5. **Modifying global state in tests**: Use task-local context with in-memory loggers instead.

## Related documentation

- ``Logger``
- ``Logger/withExistingContext(_:)``
- ``Logger/with(additionalMetadata:_:)``
- ``Logger/copy(with:)``
- <doc:003-AcceptingLoggers>
