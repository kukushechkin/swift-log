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

import Testing

@testable import Logging

/// Tests for SLG-0006: extension on `TaskLocal where Value == Logger`.
///
/// Each test declares its own `TaskLocal<Logger>` (or uses a shared test-scope one) so
/// tests are isolated by construction.
struct TaskLocalLoggerExtensionsTest {
    static let testLocal: TaskLocal<Logger> = TaskLocal(wrappedValue: Logger(label: "test-module"))

    // MARK: - Logger.withMetadata(merging:) instance method

    @Test func instanceWithMetadataMergesIntoCopy() {
        let original = Logger(label: "x")
        let merged = original.withMetadata(merging: ["a": "1", "b": "2"])
        #expect(merged[metadataKey: "a"] == "1")
        #expect(merged[metadataKey: "b"] == "2")
        // Original is untouched.
        #expect(original[metadataKey: "a"] == nil)
    }

    @Test func instanceWithMetadataInnerKeysOverrideExisting() {
        var base = Logger(label: "x")
        base[metadataKey: "k"] = "outer"
        let merged = base.withMetadata(merging: ["k": "inner"])
        #expect(merged[metadataKey: "k"] == "inner")
        #expect(base[metadataKey: "k"] == "outer")
    }

    // MARK: - withMetadata

    @Test func mergingMetadataAppearsOnNextEmission() {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        local.withMetadata(merging: ["request.id": "r1"]) {
            local.info("msg")
        }
        logging.history.assertExist(
            level: .info,
            message: "msg",
            metadata: ["request.id": "r1"]
        )
    }

    @Test func nestedMergingMetadataAccumulates() {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        local.withMetadata(merging: ["request.id": "r1"]) {
            local.withMetadata(merging: ["user.id": "u1"]) {
                local.info("msg")
            }
        }
        logging.history.assertExist(
            level: .info,
            message: "msg",
            metadata: ["request.id": "r1", "user.id": "u1"]
        )
    }

    @Test func innerMetadataOverridesOuter() {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        local.withMetadata(merging: ["key": "outer"]) {
            local.withMetadata(merging: ["key": "inner"]) {
                local.info("msg")
            }
        }
        logging.history.assertExist(level: .info, message: "msg", metadata: ["key": "inner"])
    }

    @Test func siblingMetadataScopesDoNotLeak() {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        local.withMetadata(merging: ["a": "1"]) {
            local.info("first")
        }
        local.withMetadata(merging: ["b": "2"]) {
            local.info("second")
        }
        let second = logging.history.entries.first { $0.message == "second" }
        #expect(second?.metadata?["a"] == nil)
        #expect(second?.metadata?["b"] == "2")
    }

    @Test func independentTaskLocalsDoNotInterfere() {
        let loggingA = TestLogging()
        let loggingB = TestLogging()
        let localA = TaskLocal<Logger>(
            wrappedValue: Logger(label: "a", factory: { loggingA.make(label: $0) })
        )
        let localB = TaskLocal<Logger>(
            wrappedValue: Logger(label: "b", factory: { loggingB.make(label: $0) })
        )
        localA.withMetadata(merging: ["only.in.a": "yes"]) {
            localA.info("a-line")
            localB.info("b-line")
        }
        let a = loggingA.history.entries.first { $0.message == "a-line" }
        let b = loggingB.history.entries.first { $0.message == "b-line" }
        #expect(a?.metadata?["only.in.a"] == "yes")
        #expect(b?.metadata?["only.in.a"] == nil)
    }

    // MARK: - emit forwarders

    @Test func infoForwarderEmits() {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        local.info("hello", metadata: ["k": "v"])
        logging.history.assertExist(level: .info, message: "hello", metadata: ["k": "v"])
    }

    @Test func errorForwarderEmits() {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        local.error("oops")
        logging.history.assertExist(level: .error, message: "oops")
    }

    @Test func logForwarderEmits() {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        local.log(level: .warning, "warning-msg")
        logging.history.assertExist(level: .warning, message: "warning-msg")
    }

    @Test func levelFilterSkipsForwardedEmit() {
        let logging = TestLogging()
        var logger = Logger(label: "test", factory: { logging.make(label: $0) })
        logger.logLevel = .error
        let local = TaskLocal<Logger>(wrappedValue: logger)
        local.info("filtered")
        local.error("kept")
        #expect(logging.history.entries.first { $0.message == "filtered" } == nil)
        logging.history.assertExist(level: .error, message: "kept")
    }

    // MARK: - Structured concurrency propagation

    @Test func scopePropagatesAcrossAwaitBoundary() async throws {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        try await local.withMetadata(merging: ["request.id": "r1"]) {
            local.info("before")
            await Task.yield()
            local.info("after")
        }
        logging.history.assertExist(level: .info, message: "before", metadata: ["request.id": "r1"])
        logging.history.assertExist(level: .info, message: "after", metadata: ["request.id": "r1"])
    }

    @Test func scopePropagatesIntoChildTaskButNotDetached() async {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        await local.withMetadata(merging: ["scope": "parent"]) {
            await Task {
                local.info("child")
            }.value
            await Task.detached {
                // Detached: no inheritance — outer logger is the default wrappedValue.
                #expect(local.wrappedValue[metadataKey: "scope"] == nil)
            }.value
        }
        logging.history.assertExist(level: .info, message: "child", metadata: ["scope": "parent"])
    }

    @Test func taskGroupChildrenInheritScope() async {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )
        await local.withMetadata(merging: ["scope": "parent"]) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    local.withMetadata(merging: ["task": "1"]) {
                        local.info("task 1")
                    }
                }
                group.addTask {
                    local.withMetadata(merging: ["task": "2"]) {
                        local.info("task 2")
                    }
                }
            }
        }
        logging.history.assertExist(
            level: .info,
            message: "task 1",
            metadata: ["scope": "parent", "task": "1"]
        )
        logging.history.assertExist(
            level: .info,
            message: "task 2",
            metadata: ["scope": "parent", "task": "2"]
        )
    }

    // MARK: - Error propagation

    @Test func metadataScopePropagatesThrow() {
        struct TestError: Error {}
        let local = TaskLocal<Logger>(wrappedValue: Logger(label: "test"))
        #expect(throws: TestError.self) {
            try local.withMetadata(merging: ["k": "v"]) { throw TestError() }
        }
    }

    @Test func metadataScopePropagatesThrowAsync() async {
        struct TestError: Error {}
        let local = TaskLocal<Logger>(wrappedValue: Logger(label: "test"))
        await #expect(throws: TestError.self) {
            try await local.withMetadata(merging: ["k": "v"]) {
                await Task.yield()
                throw TestError()
            }
        }
    }

    // MARK: - @TaskLocal macro-declared task-local

    /// Verify the extension methods are reachable on a `@TaskLocal`-declared static var.
    /// The macro's projected value (`$logger`) has the same visibility as the wrapped
    /// declaration; from within the declaring module the projection is reachable, and
    /// our extension on `TaskLocal where Value == Logger` applies.
    enum MacroDeclared {
        @TaskLocal static var logger: Logger = Logger(label: "macro-declared")
    }

    @Test func extensionsApplyToMacroDeclaredTaskLocal() {
        // Read the wrappedValue directly via the auto-unwrap.
        #expect(MacroDeclared.logger.label == "macro-declared")

        // Call the extension's withMetadata on the projected value, verify the closure
        // sees the augmented logger via the auto-unwrapped accessor.
        MacroDeclared.$logger.withMetadata(merging: ["request.id": "r1"]) {
            #expect(MacroDeclared.logger[metadataKey: "request.id"] == "r1")
        }

        // Call an emit forwarder on the projected value.
        let logging = TestLogging()
        MacroDeclared.$logger.withValue(Logger(label: "macro-declared", factory: { logging.make(label: $0) })) {
            MacroDeclared.$logger.info("hello via macro")
        }
        logging.history.assertExist(level: .info, message: "hello via macro")
    }

    // MARK: - File-scope declaration

    @Test func extensionsApplyToFileScopeTaskLocal() {
        #expect(fileScopeLogger.wrappedValue.label == "file-scope")
        let logging = TestLogging()
        fileScopeLogger.withValue(Logger(label: "file-scope", factory: { logging.make(label: $0) })) {
            fileScopeLogger.withMetadata(merging: ["k": "v"]) {
                fileScopeLogger.info("file-scope line")
            }
        }
        logging.history.assertExist(level: .info, message: "file-scope line", metadata: ["k": "v"])
    }

    // MARK: - Sendable boundary across await

    @Test func metadataValuesSurviveAwaitBoundary() async throws {
        let logging = TestLogging()
        let local = TaskLocal<Logger>(
            wrappedValue: Logger(label: "test", factory: { logging.make(label: $0) })
        )

        // .stringConvertible carries a Sendable instance; .dictionary nests metadata.
        let nested: Logger.Metadata = [
            "convertible": .stringConvertible(42 as Int),
            "nested": .dictionary(["inner": "v"]),
        ]

        try await local.withMetadata(merging: nested) {
            local.info("before")
            await Task.yield()
            local.info("after")
        }

        let after = logging.history.entries.first { $0.message == "after" }
        #expect(after?.metadata?["convertible"] == .stringConvertible(42 as Int))
        #expect(after?.metadata?["nested"] == .dictionary(["inner": "v"]))
    }
}

// File-scope declaration used by `extensionsApplyToFileScopeTaskLocal`.
private let fileScopeLogger: TaskLocal<Logger> = TaskLocal(wrappedValue: Logger(label: "file-scope"))
