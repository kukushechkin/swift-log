//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Logging API open source project
//
// Copyright (c) 2018-2025 Apple Inc. and the Swift Logging API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Logging API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if canImport(os) && compiler(>=6.0)
import Logging
import LoggingAttributes
import OSLogHandler
import Testing

@Suite("OSLog Handler Tests")
struct OSLogHandlerTests {
    // MARK: - Test Data

    private enum TestData {
        static let subsystem = "com.example.test"
        static let category = "test-category"
        static let userId = "user-12345"
        static let sessionId = "session-67890"
    }

    // MARK: - Initialization Tests

    @Test("OSLogHandler can be initialized")
    func testInitialization() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        let handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)
        #expect(handler.logLevel == .info)
        #expect(handler.metadata.isEmpty)
        #expect(handler.metadataProvider == nil)
    }

    @Test("OSLogHandler integrates with Logger")
    func testLoggerIntegration() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        let handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)
        let logger = Logger(label: "test") { _ in handler }
        #expect(logger.logLevel == .info)
    }

    // MARK: - Plain Metadata Tests

    @Test("OSLogHandler logs plain metadata")
    func testPlainMetadataLogging() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        let handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)
        let logger = Logger(label: "test") { _ in handler }

        logger.info("Plain message", metadata: ["key": "value"])
    }

    @Test("OSLogHandler supports all log levels")
    func testAllLogLevels() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        var handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)
        handler.logLevel = .trace
        let logger = Logger(label: "test") { _ in handler }

        logger.trace("Trace message")
        logger.debug("Debug message")
        logger.info("Info message")
        logger.notice("Notice message")
        logger.warning("Warning message")
        logger.error("Error message")
        logger.critical("Critical message")
    }

    // MARK: - Metadata with Sensitivity Tests

    @Test("OSLogHandler logs metadata with sensitivity")
    func testMetadataWithSensitivity() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        let handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)
        let logger = Logger(label: "test") { _ in handler }

        logger.info(
            "User action",
            metadata: [
                "user.id": "\(TestData.userId, sensitivity: .sensitive)",
                "action": "\("login", sensitivity: .public)",
            ]
        )
    }

    @Test("OSLogHandler handles empty metadata")
    func testEmptyMetadata() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        let handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)
        let logger = Logger(label: "test") { _ in handler }

        logger.info("Message with empty metadata", metadata: [:])
    }

    @Test("OSLogHandler handles nil metadata")
    func testNilMetadata() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        let handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)
        let logger = Logger(label: "test") { _ in handler }

        logger.info("Message")
    }

    // MARK: - Metadata Storage Tests

    @Test("Handler metadata storage via subscript")
    func testHandlerMetadataSubscript() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        var handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)

        handler[metadataKey: "key1"] = "value1"
        #expect(handler[metadataKey: "key1"]?.description == "value1")

        handler[metadataKey: "key1"] = "updated"
        #expect(handler[metadataKey: "key1"]?.description == "updated")

        handler[metadataKey: "key1"] = nil
        #expect(handler[metadataKey: "key1"] == nil)
    }

    @Test("Handler metadata with sensitivity via subscript")
    func testHandlerMetadataWithSensitivitySubscript() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        var handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)

        handler[metadataKey: "user.id"] = "\(TestData.userId, sensitivity: .sensitive)"
        #expect(handler[metadataKey: "user.id"]?.sensitivity == .sensitive)
        #expect(handler[metadataKey: "user.id"]?.description == TestData.userId)

        handler[metadataKey: "user.id"] = nil
        #expect(handler[metadataKey: "user.id"] == nil)
    }

    @Test("Handler plain metadata property")
    func testHandlerPlainMetadataProperty() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        var handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)

        handler.metadata = ["key1": "value1", "key2": "value2"]
        #expect(handler.metadata.count == 2)
        #expect(handler.metadata["key1"]?.description == "value1")
    }

    @Test("Handler metadata with sensitivity via property")
    func testHandlerMetadataWithSensitivityProperty() {
        guard #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) else {
            return
        }

        var handler = OSLogHandler(subsystem: TestData.subsystem, category: TestData.category)

        handler.metadata = [
            "public-key": "\("public-value", sensitivity: .public)",
            "private-key": "\("private-value", sensitivity: .sensitive)",
        ]

        #expect(handler.metadata.count == 2)
        #expect(handler.metadata["public-key"]?.sensitivity == .public)
        #expect(handler.metadata["private-key"]?.sensitivity == .sensitive)
    }
}
#endif
