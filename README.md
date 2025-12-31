# SwiftLog

This repository contains a logging API implementation for Swift.
SwiftLog provides a unified, performant, and ergonomic logging API that can be
adopted by libraries and applications across the Swift ecosystem.

- 📚 **Documentation** and **tutorials** are available on the [Swift Package Index](https://swiftpackageindex.com/apple/swift-log)
- 🚀 **Contributions** are welcome, please see [CONTRIBUTING.md](CONTRIBUTING.md)
- 🪪 **License** is Apache 2.0, repeated in [LICENSE.txt](LICENSE.txt)
- 🔒 **Security** issues should be reported via the process in [SECURITY.md](SECURITY.md)
- 🔀 **Available Logging Backends**: SwiftLog is an API package - you'll want to
choose from the many
[community-maintained logging backends](#available-log-handler-backends) for production use

## Quick Start

The following snippet shows how to add SwiftLog to your Swift Package:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "YourApp",
    dependencies: [
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0")
    ],
    targets: [
        .target(
            name: "YourApp",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        )
    ]
)
```

Then start logging:

```swift
import Logging

// Create a logger
let logger = Logger(label: "com.example.YourApp")

// Log at different levels
logger.info("Application started")
logger.warning("This is a warning")
logger.error("Something went wrong", metadata: ["error": "\(error)"])

// Add metadata for context
var requestLogger = logger
requestLogger[metadataKey: "request-id"] = "\(UUID())"
requestLogger.info("Processing request")
```

## Task-local logger context

SwiftLog supports task-local logger propagation, enabling implicit context passing without explicit logger parameters.
This is useful for request-scoped logging in server applications and library code that needs to log without requiring
explicit logger parameters.

### Request-scoped logging

Set context once at request entry points, automatically available throughout request processing.

```swift
import Logging

func handleHTTPRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
    return try await Logger.with(
        additionalMetadata: [
            "request.id": "\(request.id)",
            "request.method": "\(request.method)"
        ]
    ) { logger in
        logger.info("Handling request")

        let result = try await processRequest(request)

        logger.info("Request completed")

        return result
    }
}

// Deep in call stack - context automatically available
func performBusinessLogic() async {
    Logger.withExistingContext { logger in
        logger.debug("Processing")  // Includes request.id and request.method
    }
}
```

### Incremental context enrichment

Add context progressively as it becomes available.

```swift
func handleRequest(_ request: HTTPRequest) async throws -> HTTPResponse {
    return try await Logger.with(additionalMetadata: ["request.id": "\(request.id)"]) { logger in
        let user = try await authenticateUser(request)

        // Add user context for subsequent operations
        return try await Logger.with(additionalMetadata: ["user.id": "\(user.id)"]) { logger in
            return try await processAuthenticatedRequest(request, user: user)
        }
    }
}

func processAuthenticatedRequest(_ request: HTTPRequest, user: User) async throws -> HTTPResponse {
    Logger.withExistingContext { logger in
        logger.info("Processing")  // Includes both request.id and user.id
    }

    return try await performUserOperation(user)
}
```

### Library integration

Libraries can use task-local context to log without requiring explicit logger parameters.

```swift
// Library code - no logger parameter needed
public struct DatabaseClient {
    public func query(_ sql: String) async throws -> [Row] {
        Logger.withExistingContext { logger in
            logger.debug("Executing query", metadata: ["sql": "\(sql)"])
        }

        return try await executeQuery(sql)
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

### Performance-critical paths

Extract logger once before tight loops to avoid repeated TaskLocal property access.

```swift
func processLargeDataset(_ items: [Item]) async {
    Logger.withExistingContext { logger in
        logger.info("Starting batch processing")

        // Extract once for hot path
        for item in items {
            processItem(item, logger: logger)  // Pass explicitly
        }

        logger.info("Batch processing completed")
    }
}
```

### Testing with in-memory loggers

Use task-local in-memory loggers for testing without global state modification.

```swift
func testRequestHandling() async {
    let logging = InMemoryLogger()
    let logger = Logger(label: "test", factory: { logging.makeHandler(label: $0) })

    await Logger.with(handler: logger.handler) { _ in
        await Logger.with(additionalMetadata: ["request.id": "123"]) { _ in
            await handleRequest()
        }

        let logs = logging.logs
        assert(logs.contains { $0.message == "Request received" && $0.metadata["request.id"] == "123" })
    }
}
```

## Available log handler backends

The community has built numerous specialized logging backends.

A great way to discover available log backend implementations is searching the
[Swift Package Index](https://swiftpackageindex.com/search?query=swift-log)
for the `swift-log` keyword.
