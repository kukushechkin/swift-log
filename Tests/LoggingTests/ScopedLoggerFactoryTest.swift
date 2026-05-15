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

/// Tests for SLG-0007: scoped logger factory.
struct ScopedLoggerFactoryTest {
    @Test func factoryBindingRoutesLoggerInitToFactory() {
        let logging = TestLogging()
        withLoggerFactory({ label, _ in logging.make(label: label) }) {
            Logger(label: "app").info("routed")
        }
        logging.history.assertExist(level: .info, message: "routed")
    }

    @Test func factoryFallsBackToLoggingSystemOutsideScope() {
        // Outside any withLoggerFactory(_:_:) scope, the task-local is nil.
        #expect(Logger.taskLocalFactory.wrappedValue == nil)
    }

    @Test func nestedFactoryScopesReplaceOuter() {
        let outer = TestLogging()
        let inner = TestLogging()
        withLoggerFactory({ label, _ in outer.make(label: label) }) {
            withLoggerFactory({ label, _ in inner.make(label: label) }) {
                Logger(label: "app").info("inner")
            }
            Logger(label: "app").info("outer")
        }
        outer.history.assertExist(level: .info, message: "outer")
        outer.history.assertNotExist(level: .info, message: "inner")
        inner.history.assertExist(level: .info, message: "inner")
        inner.history.assertNotExist(level: .info, message: "outer")
    }

    @Test func loggerInitDoesNotMergeAnyTaskLocalMetadata() {
        // Library scenario: a logger constructed by Logger.init(label:) inside any
        // metadata-scope on an unrelated task-local is structurally isolated from that
        // task-local's metadata.
        let logging = TestLogging()
        let unrelated = TaskLocal<Logger>(wrappedValue: Logger(label: "x"))
        withLoggerFactory({ label, _ in logging.make(label: label) }) {
            unrelated.withMetadata(merging: ["request.id": "r1"]) {
                Logger(label: "lib").info("lib line")
            }
        }
        let entry = logging.history.entries.first { $0.message == "lib line" }
        #expect(entry != nil)
        #expect(entry?.metadata?["request.id"] == nil)
    }

    @Test func factoryAccessorReturnsScopedFactoryInsideScope() {
        let logging = TestLogging()
        var observedHandlerLabel: String?
        withLoggerFactory({ label, _ in logging.make(label: label) }) {
            observedHandlerLabel = (LoggingSystem.factory("probe", nil) as? TestLogHandler)?.label
        }
        #expect(observedHandlerLabel == "probe")
    }

    // MARK: - Structured concurrency propagation

    @Test func scopePropagatesAcrossAwaitBoundary() async throws {
        let logging = TestLogging()
        try await withLoggerFactory({ label, _ in logging.make(label: label) }) {
            Logger(label: "before").info("before")
            await Task.yield()
            Logger(label: "after").info("after")
        }
        logging.history.assertExist(level: .info, message: "before")
        logging.history.assertExist(level: .info, message: "after")
    }

    @Test func factoryDoesNotPropagateIntoDetachedTask() async {
        await withLoggerFactory({ _, _ in StreamLogHandler.standardOutput(label: "x") }) {
            await Task.detached {
                #expect(Logger.taskLocalFactory.wrappedValue == nil)
            }.value
        }
    }

    // MARK: - Error propagation

    @Test func factoryScopePropagatesThrow() {
        struct TestError: Error {}
        #expect(throws: TestError.self) {
            try withLoggerFactory({ label, _ in StreamLogHandler.standardOutput(label: label) }) {
                throw TestError()
            }
        }
    }

    @Test func factoryScopePropagatesThrowAsync() async {
        struct TestError: Error {}
        await #expect(throws: TestError.self) {
            try await withLoggerFactory({ label, _ in StreamLogHandler.standardOutput(label: label) }) {
                await Task.yield()
                throw TestError()
            }
        }
    }
}
