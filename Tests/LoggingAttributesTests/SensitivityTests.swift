//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Logging API open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Logging API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Logging API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import LoggingAttributes
import Testing

@testable import Logging

@Suite("Redaction Tests")
struct RedactionTests {

    // MARK: - Test Data Constants

    private enum TestData {
        static let userId = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        static let action = "login"
        static let sessionId = UUID(uuidString: "87654321-4321-8765-4321-876543218765")!
        static let requestId = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
        static let redactionMarker = SensitivityAwareLogHandlerWrapper.redactionMarker
    }

    // MARK: - Test Fixtures

    private func makeRecorderLogger() -> (RedactionLogRecorder, Logger) {
        let recorder = RedactionLogRecorder()
        let handler = RedactionTestLogHandler(recorder: recorder)
        var logger = Logger(label: "test") { _ in handler }
        logger.logLevel = .trace
        return (recorder, logger)
    }

    private func makeStreamLogger(
        sensitivityBehavior: SensitivityAwareLogHandlerWrapper.SensitivityBehavior = .redact
    )
        -> (TestOutputStream, Logger)
    {
        let stream = TestOutputStream()
        let streamHandler = StreamLogHandler(label: "test", stream: stream, metadataProvider: nil)
        let handler = SensitivityAwareLogHandlerWrapper(
            wrapping: streamHandler,
            sensitivityBehavior: sensitivityBehavior
        )
        return (stream, Logger(label: "test") { _ in handler })
    }

    // MARK: - Tests

    @Test("Sensitivity enum properties")
    func testSensitivity() {
        #expect("\(Logger.Sensitivity.sensitive)" == "sensitive")
        #expect("\(Logger.Sensitivity.public)" == "public")
        #expect(Logger.Sensitivity.allCases.contains(.sensitive))
        #expect(Logger.Sensitivity.allCases.contains(.public))
    }

    @Test("MetadataValueAttributes initialization")
    func testMetadataValueAttributes() {
        let defaultAttrs = Logger.MetadataValueAttributes()
        #expect(defaultAttrs.sensitivity == nil)

        let publicAttrs = Logger.MetadataValueAttributes(sensitivity: .public)
        #expect(publicAttrs.sensitivity == .public)

        let redactAttrs = Logger.MetadataValueAttributes(sensitivity: .sensitive)
        #expect(redactAttrs.sensitivity == .sensitive)
    }

    @Test("MetadataValue carries sensitivity via string interpolation")
    func testMetadataValueCarriesSensitivity() {
        let sensitiveValue: Logger.MetadataValue = "\(TestData.userId, sensitivity: .sensitive)"
        #expect(sensitiveValue.description == TestData.userId.uuidString)
        #expect(sensitiveValue.sensitivity == .sensitive)

        let publicValue: Logger.MetadataValue = "\(TestData.action, sensitivity: .public)"
        #expect(publicValue.description == TestData.action)
        #expect(publicValue.sensitivity == .public)
    }

    @Test("SensitivityAwareLogHandlerWrapper redacts redacted metadata")
    func testSensitivityAwareLogHandlerWrapperRedaction() {
        let (stream, logger) = makeStreamLogger()

        logger.log(
            level: .info,
            "User action",
            metadata: [
                "user.id": "\(TestData.userId, sensitivity: .sensitive)",
                "action": "\(TestData.action, sensitivity: .public)",
                "session.id": "\(TestData.sessionId, sensitivity: .sensitive)",
            ]
        )

        #expect(stream.output.contains("action=\(TestData.action)"))
        #expect(stream.output.contains("user.id=\(TestData.redactionMarker)"))
        #expect(stream.output.contains("session.id=\(TestData.redactionMarker)"))
        #expect(!stream.output.contains(TestData.userId.uuidString))
        #expect(!stream.output.contains(TestData.sessionId.uuidString))
    }

    @Test("SensitivityAwareLogHandlerWrapper logs redacted metadata when configured")
    func testSensitivityAwareLogHandlerWrapperLogsRedacted() {
        let (stream, logger) = makeStreamLogger(sensitivityBehavior: .log)

        logger.log(
            level: .info,
            "User action",
            metadata: [
                "user.id": "\(TestData.userId, sensitivity: .sensitive)",
                "action": "\(TestData.action, sensitivity: .public)",
            ]
        )

        #expect(stream.output.contains("user.id=\(TestData.userId.uuidString)"))
        #expect(stream.output.contains("action=\(TestData.action)"))
        #expect(!stream.output.contains(TestData.redactionMarker))
    }

    @Test("SensitivityAwareLogHandlerWrapper factory pattern works")
    func testSensitivityAwareLogHandlerWrapperFactoryPattern() {
        let streamHandler1 = StreamLogHandler.standardOutput(label: "stdout-test")
        let wrapper1 = SensitivityAwareLogHandlerWrapper(wrapping: streamHandler1)
        #expect(wrapper1.logLevel == .info)
        #expect(wrapper1.sensitivityBehavior == .redact)

        let streamHandler2 = StreamLogHandler.standardError(label: "stderr-test")
        let wrapper2 = SensitivityAwareLogHandlerWrapper(wrapping: streamHandler2, sensitivityBehavior: .log)
        #expect(wrapper2.logLevel == .info)
        #expect(wrapper2.sensitivityBehavior == .log)

        let provider = Logger.MetadataProvider { ["env": "test"] }
        let streamHandler3 = StreamLogHandler.standardOutput(label: "test")
        var wrapper3 = SensitivityAwareLogHandlerWrapper(wrapping: streamHandler3)
        wrapper3.metadataProvider = provider
        #expect(wrapper3.metadataProvider != nil)
        #expect(wrapper3.sensitivityBehavior == .redact)
    }

    @Test("SensitivityAwareLogHandlerWrapper handles plain metadata")
    func testSensitivityAwareLogHandlerWrapperPlainMetadata() {
        let stream = TestOutputStream()

        let streamHandler = StreamLogHandler(label: "test", stream: stream, metadataProvider: nil)
        let handler = SensitivityAwareLogHandlerWrapper(wrapping: streamHandler)

        let logger = Logger(label: "test") { _ in handler }

        logger.info("Plain message", metadata: ["key": "value", "count": "42"])

        #expect(stream.output.contains("key=value"))
        #expect(stream.output.contains("count=42"))
    }

    @Test("SensitivityAwareLogHandlerWrapper merges global metadata")
    func testSensitivityAwareLogHandlerWrapperGlobalMetadata() {
        let stream = TestOutputStream()
        let streamHandler = StreamLogHandler(label: "test", stream: stream, metadataProvider: nil)
        var handler = SensitivityAwareLogHandlerWrapper(wrapping: streamHandler, sensitivityBehavior: .redact)
        handler[metadataKey: "service"] = "auth"
        handler[metadataKey: "version"] = "1.0"

        let logger = Logger(label: "test") { _ in handler }

        logger.log(
            level: .info,
            "Request",
            metadata: [
                "user.id": "\(TestData.userId, sensitivity: .sensitive)",
                "request.id": "\(TestData.requestId, sensitivity: .public)",
            ]
        )

        #expect(stream.output.contains("service=auth"))
        #expect(stream.output.contains("version=1.0"))
        #expect(stream.output.contains("request.id=\(TestData.requestId.uuidString)"))
        #expect(stream.output.contains("user.id=\(TestData.redactionMarker)"))
        #expect(!stream.output.contains(TestData.userId.uuidString))
    }

    @Test("Handler sensitivityBehavior property")
    func testHandlerSensitivityBehavior() {
        let streamHandler = StreamLogHandler.standardOutput(label: "test")
        var handler = SensitivityAwareLogHandlerWrapper(wrapping: streamHandler)

        #expect(handler.sensitivityBehavior == .redact)

        handler.sensitivityBehavior = .log
        #expect(handler.sensitivityBehavior == .log)

        var handler2 = handler
        handler2.sensitivityBehavior = .redact
        #expect(handler.sensitivityBehavior == .log)
        #expect(handler2.sensitivityBehavior == .redact)
    }

    @Test("SensitivityAwareLogHandlerWrapper strips sensitivity attribute after redaction")
    func testSensitivityAttributeStrippedAfterRedaction() {
        let recorder = RedactionLogRecorder()
        let innerHandler = RedactionTestLogHandler(recorder: recorder)
        let wrapper = SensitivityAwareLogHandlerWrapper(
            wrapping: innerHandler,
            sensitivityBehavior: .redact
        )
        var logger = Logger(label: "test") { _ in wrapper }
        logger.logLevel = .trace

        logger.log(
            level: .info,
            "User action",
            metadata: [
                "user.id": "\(TestData.userId, sensitivity: .sensitive)",
                "action": "\(TestData.action, sensitivity: .public)",
            ]
        )

        #expect(recorder.messages.count == 1)
        let finalMetadata = recorder.messages[0].metadata

        // The redacted value should have the redaction marker and NO sensitivity attribute
        #expect(finalMetadata?["user.id"]?.description == TestData.redactionMarker)
        // After redaction, attributes are stripped (it's now a plain .string)
        #expect(finalMetadata?["user.id"]?.sensitivity == nil)

        // The public value should retain its sensitivity attribute
        #expect(finalMetadata?["action"]?.description == TestData.action)
        #expect(finalMetadata?["action"]?.sensitivity == .public)
    }

    @Test("Logger metadata with sensitivity via string interpolation")
    func testLoggerMetadataWithSensitivity() {
        let (_, logger) = makeRecorderLogger()
        var mutableLogger = logger

        mutableLogger[metadataKey: "user.id"] = "\(TestData.userId, sensitivity: .sensitive)"
        mutableLogger[metadataKey: "action"] = "\(TestData.action, sensitivity: .public)"

        #expect(mutableLogger[metadataKey: "user.id"]?.sensitivity == .sensitive)
        #expect(mutableLogger[metadataKey: "action"]?.sensitivity == .public)
    }

    @Test("Logger value semantics for metadata with attributes")
    func testLoggerValueSemanticsMetadataWithAttributes() {
        let recorder = RedactionLogRecorder()
        var logger1 = Logger(label: "test") { _ in RedactionTestLogHandler(recorder: recorder) }

        logger1[metadataKey: "key1"] = "\("value1", sensitivity: .sensitive)"

        var logger2 = logger1
        logger2[metadataKey: "key2"] = "\("value2", sensitivity: .public)"

        #expect(logger1[metadataKey: "key1"]?.description == "value1")
        #expect(logger1[metadataKey: "key2"] == nil)

        #expect(logger2[metadataKey: "key1"]?.description == "value1")
        #expect(logger2[metadataKey: "key2"]?.description == "value2")
    }

    @Test("String interpolation with sensitivity parameter")
    func testStringInterpolationWithSensitivity() {
        let redactedValue: Logger.MetadataValue = "\(TestData.userId, sensitivity: .sensitive)"
        #expect(redactedValue.description == TestData.userId.uuidString)
        #expect(redactedValue.sensitivity == .sensitive)

        let publicValue: Logger.MetadataValue = "\(TestData.action, sensitivity: .public)"
        #expect(publicValue.description == TestData.action)
        #expect(publicValue.sensitivity == .public)

        // Test multiple interpolations (strictest sensitivity wins)
        let mixedRedactedFirst: Logger.MetadataValue =
            "User \(TestData.userId, sensitivity: .sensitive) performed \(TestData.action, sensitivity: .public)"
        #expect(
            mixedRedactedFirst.description == "User \(TestData.userId.uuidString) performed \(TestData.action)"
        )
        #expect(mixedRedactedFirst.sensitivity == .sensitive)

        let mixedPublicFirst: Logger.MetadataValue =
            "User \(TestData.userId, sensitivity: .public) performed \(TestData.action, sensitivity: .sensitive)"
        #expect(mixedPublicFirst.description == "User \(TestData.userId.uuidString) performed \(TestData.action)")
        #expect(mixedPublicFirst.sensitivity == .sensitive)

        // Test string literal (no sensitivity)
        let literal: Logger.MetadataValue = "literal value"
        #expect(literal.description == "literal value")
        #expect(literal.sensitivity == nil)

        // Test interpolation without sensitivity parameter
        let noSensitivity: Logger.MetadataValue = "\(TestData.userId)"
        #expect(noSensitivity.description == TestData.userId.uuidString)
        #expect(noSensitivity.sensitivity == nil)
    }

    @Test("String interpolation in logging")
    func testStringInterpolationInLogging() {
        let (recorder, logger) = makeRecorderLogger()

        logger.log(
            level: .info,
            "User action",
            metadata: [
                "user.id": "\(TestData.userId, sensitivity: .sensitive)",
                "action": "\(TestData.action, sensitivity: .public)",
                "session": "sess-\(TestData.userId, sensitivity: .sensitive)",
            ]
        )

        #expect(recorder.messages.count == 1)
        let metadata = recorder.messages[0].metadata
        #expect(metadata != nil)
        #expect(metadata?["user.id"]?.sensitivity == .sensitive)
        #expect(metadata?["user.id"]?.description == TestData.userId.uuidString)
        #expect(metadata?["action"]?.sensitivity == .public)
        #expect(metadata?["action"]?.description == TestData.action)
        #expect(metadata?["session"]?.sensitivity == .sensitive)
        #expect(metadata?["session"]?.description == "sess-\(TestData.userId.uuidString)")
    }

    @Test("MetadataProvider returns metadata with attributes")
    func testMetadataProviderWithAttributes() {
        let provider = Logger.MetadataProvider {
            [
                "public-key": "\("public-value", sensitivity: .public)",
                "private-key": "\("private-value", sensitivity: .sensitive)",
                "plain-key": "plain-value",
            ]
        }

        let metadata = provider.get()
        #expect(metadata.count == 3)
        #expect(metadata["public-key"]?.sensitivity == .public)
        #expect(metadata["private-key"]?.sensitivity == .sensitive)
        #expect(metadata["plain-key"]?.sensitivity == nil)
        #expect(metadata["public-key"]?.description == "public-value")
        #expect(metadata["private-key"]?.description == "private-value")
    }

    @Test("MetadataProvider multiplex with empty provider")
    func testMetadataProviderMultiplexWithEmptyProvider() {
        let emptyProvider = Logger.MetadataProvider { [:] }
        let nonEmptyProvider = Logger.MetadataProvider { ["key": "value"] }

        let multiplexed = Logger.MetadataProvider.multiplex([emptyProvider, nonEmptyProvider])
        #expect(multiplexed != nil)

        let metadata = multiplexed?.get()
        #expect(metadata != nil)
        #expect(metadata?.count == 1)
        #expect(metadata?["key"]?.description == "value")

        let multiplexedEmpty = Logger.MetadataProvider.multiplex([emptyProvider, emptyProvider])
        #expect(multiplexedEmpty != nil)

        let emptyMetadata = multiplexedEmpty?.get()
        #expect(emptyMetadata != nil)
        #expect(emptyMetadata?.isEmpty == true)
    }

    @Test("MetadataProvider multiplex with attributed values")
    func testMetadataProviderMultiplexWithAttributedValues() {
        let plainProvider = Logger.MetadataProvider {
            ["env": "production", "host": "server-1"]
        }
        let attributedProvider = Logger.MetadataProvider {
            [
                "user-id": "\("u-123", sensitivity: .sensitive)",
                "request-id": "\("r-456", sensitivity: .public)",
            ]
        }

        let multiplexed = Logger.MetadataProvider.multiplex([plainProvider, attributedProvider])
        #expect(multiplexed != nil)

        let metadata = multiplexed!.get()
        #expect(metadata.count == 4)
        #expect(metadata["env"]?.description == "production")
        #expect(metadata["env"]?.sensitivity == nil)
        #expect(metadata["user-id"]?.sensitivity == .sensitive)
        #expect(metadata["request-id"]?.sensitivity == .public)
    }

    @Test("MetadataProvider multiplex last-writer-wins")
    func testMetadataProviderMultiplexLastWriterWins() {
        let provider1 = Logger.MetadataProvider {
            ["key": "\("from-first", sensitivity: .public)"]
        }
        let provider2 = Logger.MetadataProvider {
            ["key": "\("from-second", sensitivity: .sensitive)"]
        }

        let multiplexed = Logger.MetadataProvider.multiplex([provider1, provider2])!
        let metadata = multiplexed.get()

        #expect(metadata["key"]?.description == "from-second")
        #expect(metadata["key"]?.sensitivity == .sensitive)
    }

    @Test(
        "Logger convenience methods with metadata carrying attributes",
        arguments: [
            Logger.Level.trace,
            .debug,
            .info,
            .notice,
            .warning,
            .error,
            .critical,
        ]
    )
    func testLoggerConvenienceMethodsWithSensitiveMetadata(level: Logger.Level) {
        let (stream, logger) = makeStreamLogger()
        var mutableLogger = logger
        mutableLogger.logLevel = .trace

        mutableLogger.log(
            level: level,
            "\(level) message",
            metadata: [
                "public-\(level)": "\("\(level)-public", sensitivity: .public)",
                "private-\(level)": "\("\(level)-private", sensitivity: .sensitive)",
            ]
        )

        #expect(stream.output.contains("\(level) message"))
        #expect(stream.output.contains("public-\(level)=\(level)-public"))
        #expect(stream.output.contains("private-\(level)=\(TestData.redactionMarker)"))
    }

    @Test("MetadataValue description always shows raw values regardless of sensitivity")
    func testMetadataValueDescription() {
        let publicValue: Logger.MetadataValue = "\("visible-data", sensitivity: .public)"
        #expect(publicValue.description == "visible-data")

        let sensitiveValue: Logger.MetadataValue = "\("secret-data", sensitivity: .sensitive)"
        #expect(sensitiveValue.description == "secret-data")

        let plainValue: Logger.MetadataValue = "\("plain")"
        #expect(plainValue.description == "plain")
    }

}

// MARK: - Test Helpers

internal final class TestOutputStream: TextOutputStream, @unchecked Sendable {
    var output: String = ""

    func write(_ string: String) {
        self.output += string
    }
}

internal final class RedactionLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?)] = []

    func record(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?
    ) {
        self.lock.withLock {
            self._messages.append((level: level, message: message, metadata: metadata))
        }
    }

    var messages: [(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?)] {
        self.lock.withLock { self._messages }
    }
}

internal struct RedactionTestLogHandler: LogHandler {
    var logLevel: Logger.Level = .trace
    var metadataProvider: Logger.MetadataProvider?
    private let recorder: RedactionLogRecorder

    var metadata = Logger.Metadata()

    init(recorder: RedactionLogRecorder) {
        self.recorder = recorder
    }

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { self.metadata[metadataKey] }
        set { self.metadata[metadataKey] = newValue }
    }

    func log(event: LogEvent) {
        var merged = self.metadata

        if let provider = self.metadataProvider {
            let provided = provider.get()
            merged.merge(provided, uniquingKeysWith: { _, rhs in rhs })
        }

        if let eventMetadata = event.metadata {
            merged.merge(eventMetadata, uniquingKeysWith: { _, rhs in rhs })
        }

        self.recorder.record(
            level: event.level,
            message: event.message,
            metadata: merged.isEmpty ? nil : merged
        )
    }
}
