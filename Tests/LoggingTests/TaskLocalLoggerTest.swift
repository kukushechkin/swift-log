//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Logging API open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift Logging API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Logging API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import Testing

@testable import Logging

/// Tests for task-local logger functionality.
///
/// These tests demonstrate that task-local storage provides automatic isolation
/// between tasks, enabling concurrent test execution without serialization.
/// Each task maintains its own independent logger context.
struct TaskLocalLoggerTest {
    // MARK: - Basic task-local access

    @Test func withExistingContextProvidesDefaultLogger() {
        // Test that withExistingContext provides a logger even when no context is set
        Logger.withExistingContext { logger in
            #expect(logger.label == "task-local")
        }
    }

    @Test func withExistingContextSyncVoid() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        Logger.with(handler: logger.handler) { _ in
            Logger.with(additionalMetadata: ["test": "value"]) { logger in
                logger.info("test message")
            }
        }

        logging.history.assertExist(
            level: .info,
            message: "test message",
            metadata: ["test": "value"]
        )
    }

    @Test func withExistingContextSyncReturning() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        let result = Logger.with(handler: logger.handler) { _ in
            Logger.with(additionalMetadata: ["test": "value"]) { logger -> Int in
                logger.info("computing")
                return 42
            }
        }

        #expect(result == 42)
        logging.history.assertExist(level: .info, message: "computing")
    }

    @Test func withExistingContextAsyncVoid() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        await Logger.with(handler: logger.handler) { _ in
            await Logger.with(additionalMetadata: ["test": "async"]) { logger in
                logger.info("async message")
            }
        }

        logging.history.assertExist(
            level: .info,
            message: "async message",
            metadata: ["test": "async"]
        )
    }

    @Test func withExistingContextAsyncReturning() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        let result = await Logger.with(handler: logger.handler) { _ in
            await Logger.with(additionalMetadata: ["test": "async"]) { logger -> String in
                logger.info("computing async")
                return "result"
            }
        }

        #expect(result == "result")
        logging.history.assertExist(level: .info, message: "computing async")
    }

    // MARK: - Static Logger.with() methods

    @Test func staticWithMetadataSyncVoid() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        Logger.with(handler: logger.handler) { _ in
            Logger.with(additionalMetadata: ["key": "value"]) { logger in
                logger.info("test")
            }
        }

        logging.history.assertExist(
            level: .info,
            message: "test",
            metadata: ["key": "value"]
        )
    }

    @Test func staticWithMetadataSyncReturning() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        let result = Logger.with(handler: logger.handler) { _ in
            Logger.with(additionalMetadata: ["key": "value"]) { logger -> Int in
                logger.info("computing")
                return 100
            }
        }

        #expect(result == 100)
        logging.history.assertExist(level: .info, message: "computing")
    }

    @Test func staticWithMetadataAsyncVoid() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        await Logger.with(handler: logger.handler) { _ in
            await Logger.with(additionalMetadata: ["async": "true"]) { logger in
                logger.info("async test")
            }
        }

        logging.history.assertExist(
            level: .info,
            message: "async test",
            metadata: ["async": "true"]
        )
    }

    @Test func staticWithMetadataAsyncReturning() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        let result = await Logger.with(handler: logger.handler) { _ in
            await Logger.with(additionalMetadata: ["async": "true"]) { logger -> String in
                logger.info("async computing")
                return "async result"
            }
        }

        #expect(result == "async result")
        logging.history.assertExist(level: .info, message: "async computing")
    }

    @Test func staticWithLogLevel() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        Logger.with(handler: logger.handler) { _ in
            Logger.with(logLevel: .warning) { logger in
                logger.debug("should not appear")
                logger.warning("should appear")
            }
        }

        logging.history.assertNotExist(level: .debug, message: "should not appear")
        logging.history.assertExist(level: .warning, message: "should appear")
    }

    @Test func staticWithHandler() {
        let logging1 = TestLogging()
        let logging2 = TestLogging()
        let logger = Logger(label: "test", factory: { logging1.make(label: $0) })

        let customHandler = logging2.make(label: "custom")

        Logger.with(handler: logger.handler) { _ in
            Logger.with(handler: customHandler) { logger in
                logger.info("custom handler message")
            }
        }

        // Should appear in custom handler (logging2), not default (logging1)
        logging1.history.assertNotExist(level: .info, message: "custom handler message")
        logging2.history.assertExist(level: .info, message: "custom handler message")
    }

    @Test func staticWithMetadataAndLogLevel() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        Logger.with(handler: logger.handler) { _ in
            Logger.with(additionalMetadata: ["combined": "test"], logLevel: .error) { logger in
                logger.info("should not appear")
                logger.error("should appear")
            }
        }

        logging.history.assertNotExist(level: .info, message: "should not appear")
        logging.history.assertExist(
            level: .error,
            message: "should appear",
            metadata: ["combined": "test"]
        )
    }

    // MARK: - Metadata accumulation

    @Test func nestedStaticWithAccumulatesMetadata() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        Logger.with(handler: logger.handler) { _ in
            Logger.with(additionalMetadata: ["level1": "first"]) { logger in
                logger.info("level 1")

                Logger.with(additionalMetadata: ["level2": "second"]) { logger in
                    logger.info("level 2")
                }
            }
        }

        logging.history.assertExist(
            level: .info,
            message: "level 1",
            metadata: ["level1": "first"]
        )
        logging.history.assertExist(
            level: .info,
            message: "level 2",
            metadata: ["level1": "first", "level2": "second"]
        )
    }

    @Test func nestedMetadataOverrides() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        Logger.with(handler: logger.handler) { _ in
            Logger.with(additionalMetadata: ["key": "original"]) { logger in
                Logger.with(additionalMetadata: ["key": "override"]) { logger in
                    logger.info("test")
                }
            }
        }

        logging.history.assertExist(
            level: .info,
            message: "test",
            metadata: ["key": "override"]
        )
    }

    @Test func deeplyNestedMetadata() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        Logger.with(handler: logger.handler) { _ in
            Logger.with(additionalMetadata: ["depth": "1"]) { logger in
                Logger.with(additionalMetadata: ["depth": "2"]) { logger in
                    Logger.with(additionalMetadata: ["depth": "3"]) { logger in
                        Logger.with(additionalMetadata: ["depth": "4"]) { logger in
                            logger.info("deep")
                        }
                    }
                }
            }
        }

        logging.history.assertExist(
            level: .info,
            message: "deep",
            metadata: ["depth": "4"]
        )
    }

    // MARK: - Task isolation (enables concurrent tests!)

    @Test func tasksHaveIndependentContext() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        await Logger.with(handler: logger.handler) { _ in
            await withTaskGroup(of: Void.self) { group in
                // Task 1
                group.addTask {
                    await Logger.with(additionalMetadata: ["task": "1"]) { logger in
                        logger.info("task 1 message")
                    }
                }

                // Task 2
                group.addTask {
                    await Logger.with(additionalMetadata: ["task": "2"]) { logger in
                        logger.info("task 2 message")
                    }
                }

                // Task 3
                group.addTask {
                    await Logger.withExistingContext { logger in
                        // No context set - uses parent task's logger
                        logger.info("task 3 message")
                    }
                }
            }
        }

        // Each task logged with its own independent metadata
        logging.history.assertExist(
            level: .info,
            message: "task 1 message",
            metadata: ["task": "1"]
        )
        logging.history.assertExist(
            level: .info,
            message: "task 2 message",
            metadata: ["task": "2"]
        )
        logging.history.assertExist(level: .info, message: "task 3 message")
    }

    @Test func childTaskInheritsParentContext() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        await Logger.with(handler: logger.handler) { _ in
            await Logger.with(additionalMetadata: ["parent": "value"]) { logger in
                logger.info("parent message")

                // Create child task
                await Task {
                    Logger.withExistingContext { logger in
                        logger.info("child message")
                    }
                }.value
            }
        }

        // Both parent and child should have the metadata
        logging.history.assertExist(
            level: .info,
            message: "parent message",
            metadata: ["parent": "value"]
        )
        logging.history.assertExist(
            level: .info,
            message: "child message",
            metadata: ["parent": "value"]
        )
    }

    @Test func childTaskCanOverrideContext() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        await Logger.with(handler: logger.handler) { _ in
            await Logger.with(additionalMetadata: ["parent": "original"]) { logger in
                logger.info("parent")

                // Child overrides context
                await Task {
                    await Logger.with(additionalMetadata: ["parent": "overridden"]) { logger in
                        logger.info("child")
                    }
                }.value

                // Parent context unchanged after child completes
                logger.info("parent again")
            }
        }

        logging.history.assertExist(
            level: .info,
            message: "parent",
            metadata: ["parent": "original"]
        )
        logging.history.assertExist(
            level: .info,
            message: "child",
            metadata: ["parent": "overridden"]
        )
        logging.history.assertExist(
            level: .info,
            message: "parent again",
            metadata: ["parent": "original"]
        )
    }

    // MARK: - Async propagation

    @Test func contextPreservedAcrossAwaitBoundaries() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        await Logger.with(handler: logger.handler) { _ in
            await Logger.with(additionalMetadata: ["request": "123"]) { logger in
                logger.info("before await")

                // Simulate async work
                await Task.sleep(1)

                logger.info("after await")
            }
        }

        // Context preserved across await
        logging.history.assertExist(
            level: .info,
            message: "before await",
            metadata: ["request": "123"]
        )
        logging.history.assertExist(
            level: .info,
            message: "after await",
            metadata: ["request": "123"]
        )
    }

    @Test func contextPreservedThroughAsyncFunctions() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        func innerAsync() async {
            Logger.withExistingContext { logger in
                logger.info("inner function")
            }
        }

        func outerAsync() async {
            Logger.withExistingContext { logger in
                logger.info("outer before")
            }

            await innerAsync()

            Logger.withExistingContext { logger in
                logger.info("outer after")
            }
        }

        await Logger.with(handler: logger.handler) { _ in
            await Logger.with(additionalMetadata: ["flow": "async"]) { logger in
                await outerAsync()
            }
        }

        // All functions see the same context
        logging.history.assertExist(
            level: .info,
            message: "outer before",
            metadata: ["flow": "async"]
        )
        logging.history.assertExist(
            level: .info,
            message: "inner function",
            metadata: ["flow": "async"]
        )
        logging.history.assertExist(
            level: .info,
            message: "outer after",
            metadata: ["flow": "async"]
        )
    }

    // MARK: - Log level modification

    @Test func logLevelFilteringWorks() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        Logger.with(handler: logger.handler) { _ in
            Logger.with(logLevel: .warning) { logger in
                logger.trace("trace - should not appear")
                logger.debug("debug - should not appear")
                logger.info("info - should not appear")
                logger.warning("warning - should appear")
                logger.error("error - should appear")
            }
        }

        #expect(logging.history.entries.count == 2)
        logging.history.assertNotExist(level: .trace, message: "trace - should not appear")
        logging.history.assertNotExist(level: .debug, message: "debug - should not appear")
        logging.history.assertNotExist(level: .info, message: "info - should not appear")
        logging.history.assertExist(level: .warning, message: "warning - should appear")
        logging.history.assertExist(level: .error, message: "error - should appear")
    }

    @Test func logLevelCanBeChanged() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        Logger.with(handler: logger.handler) { _ in
            Logger.with(logLevel: .error) { logger in
                logger.info("first - should not appear")

                Logger.with(logLevel: .info) { logger in
                    logger.info("second - should appear")
                }

                logger.info("third - should not appear")
            }
        }

        logging.history.assertNotExist(level: .info, message: "first - should not appear")
        logging.history.assertExist(level: .info, message: "second - should appear")
        logging.history.assertNotExist(level: .info, message: "third - should not appear")
    }

    // MARK: - Instance copy() methods

    @Test func copyWithMetadata() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        let copied = logger.copy(with: ["copied": "metadata"])

        copied.info("test message")

        logging.history.assertExist(
            level: .info,
            message: "test message",
            metadata: ["copied": "metadata"]
        )
    }

    @Test func copyWithLogLevel() {
        let logging = TestLogging()
        var logger = Logger(label: "test", factory: { logging.make(label: $0) })
        logger.logLevel = .error

        let copied = logger.copy(logLevel: .debug)

        copied.debug("should appear")
        logger.debug("should not appear")

        #expect(logging.history.entries.count == 1)
        logging.history.assertExist(level: .debug, message: "should appear")
    }

    @Test func copyWithHandler() {
        let logging1 = TestLogging()
        let logging2 = TestLogging()
        let logger = Logger(label: "test", factory: { logging1.make(label: $0) })

        let copied = logger.copy(handler: logging2.make(label: "copied"))

        logger.info("original")
        copied.info("copied")

        logging1.history.assertExist(level: .info, message: "original")
        logging1.history.assertNotExist(level: .info, message: "copied")

        logging2.history.assertNotExist(level: .info, message: "original")
        logging2.history.assertExist(level: .info, message: "copied")
    }

    @Test func copyDoesNotMutateOriginal() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        let copied = logger.copy(with: ["key": "value"])

        logger.info("original")
        copied.info("copied")

        // Original should not have the metadata
        logging.history.assertExist(level: .info, message: "original", metadata: nil)
        logging.history.assertExist(
            level: .info,
            message: "copied",
            metadata: ["key": "value"]
        )
    }

    // MARK: - Real-world scenarios

    @Test func requestHandlerPattern() async {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        func processRequest(id: String) async {
            await Logger.with(additionalMetadata: ["request.id": "\(id)"]) { logger in
                logger.info("Request received")

                await authenticateUser(username: "alice")

                logger.info("Request completed")
            }
        }

        func authenticateUser(username: String) async {
            await Logger.with(additionalMetadata: ["user": "\(username)"]) { logger in
                logger.debug("Authenticating user")
            }
        }

        await Logger.with(handler: logger.handler) { _ in
            await processRequest(id: "req-123")
        }

        logging.history.assertExist(
            level: .info,
            message: "Request received",
            metadata: ["request.id": "req-123"]
        )
        logging.history.assertExist(
            level: .debug,
            message: "Authenticating user",
            metadata: ["request.id": "req-123", "user": "alice"]
        )
        logging.history.assertExist(
            level: .info,
            message: "Request completed",
            metadata: ["request.id": "req-123"]
        )
    }

    @Test func libraryEntryPointPattern() {
        let logging = TestLogging()
        let logger = Logger(label: "test", factory: { logging.make(label: $0) })

        // Library code that doesn't require logger parameter
        struct DatabaseClient {
            func query(_ sql: String) {
                Logger.withExistingContext { logger in
                    logger.debug("Executing query", metadata: ["sql": "\(sql)"])
                }
            }
        }

        // Application sets up context
        Logger.with(handler: logger.handler) { _ in
            Logger.with(additionalMetadata: ["request.id": "123"]) { logger in
                let db = DatabaseClient()
                db.query("SELECT * FROM users")
            }
        }

        logging.history.assertExist(
            level: .debug,
            message: "Executing query",
            metadata: ["request.id": "123", "sql": "SELECT * FROM users"]
        )
    }
}
