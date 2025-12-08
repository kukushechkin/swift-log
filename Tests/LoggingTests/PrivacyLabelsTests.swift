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

import Testing

@testable import Logging

@Suite("Privacy Labels Tests")
struct PrivacyLabelsTests {

    @Test("PrivacyLevel enum properties")
    func testPrivacyLevel() {
        #expect(Logger.PrivacyLevel.private.rawValue == "private")
        #expect(Logger.PrivacyLevel.public.rawValue == "public")
        #expect(Logger.PrivacyLevel.allCases.contains(.private))
        #expect(Logger.PrivacyLevel.allCases.contains(.public))
    }

    @Test("MetadataValueProperties initialization")
    func testMetadataValueProperties() {
        let defaultProps = Logger.MetadataValueProperties()
        #expect(defaultProps.privacyLevel == .private)

        let publicProps = Logger.MetadataValueProperties(privacyLevel: .public)
        #expect(publicProps.privacyLevel == .public)

        let privateProps = Logger.MetadataValueProperties(privacyLevel: .private)
        #expect(privateProps.privacyLevel == .private)
    }

    @Test("AttributedMetadataValue initialization")
    func testAttributedMetadataValue() {
        let value = Logger.MetadataValue.string("test")
        let properties = Logger.MetadataValueProperties(privacyLevel: .public)

        let attributed1 = Logger.AttributedMetadataValue(value, properties: properties)
        #expect(attributed1.value.description == "test")
        #expect(attributed1.properties.privacyLevel == .public)

        let attributed2 = Logger.AttributedMetadataValue(value, privacy: .private)
        #expect(attributed2.value.description == "test")
        #expect(attributed2.properties.privacyLevel == .private)
    }

    @Test("MetadataValue convenience methods")
    func testMetadataValueConvenienceMethods() {
        let stringValue = Logger.MetadataValue.string("sensitive")

        let privateValue = stringValue.private()
        #expect(privateValue.value.description == "sensitive")
        #expect(privateValue.properties.privacyLevel == .private)

        let publicValue = stringValue.public()
        #expect(publicValue.value.description == "sensitive")
        #expect(publicValue.properties.privacyLevel == .public)

        let attributedValue = stringValue.attributed(privacy: .public)
        #expect(attributedValue.value.description == "sensitive")
        #expect(attributedValue.properties.privacyLevel == .public)
    }

    @Test("String convenience methods")
    func testStringConvenienceMethods() {
        let testString = "sensitive-data"

        let privateValue = testString.private()
        #expect(privateValue.value.description == "sensitive-data")
        #expect(privateValue.properties.privacyLevel == .private)

        let publicValue = testString.public()
        #expect(publicValue.value.description == "sensitive-data")
        #expect(publicValue.properties.privacyLevel == .public)

        let attributedValue = testString.attributed(privacy: .public)
        #expect(attributedValue.value.description == "sensitive-data")
        #expect(attributedValue.properties.privacyLevel == .public)
    }

    @Test("Fluent API usage")
    func testFluentAPI() {
        // Test the fluent API as described in the proposal - now with both MetadataValue and String syntax
        let metadata: Logger.AttributedMetadata = [
            "user.id": Logger.MetadataValue.string("12345").private(),
            "action": Logger.MetadataValue.string("login").public(),
            "timestamp": Logger.MetadataValue.string("2024-01-01").public(),
            "settings": Logger.MetadataValue.dictionary(["theme": "dark", "notifications": "enabled"]).private(),
            "features": Logger.MetadataValue.array(["feature1", "feature2"]).public(),
            // New string convenience syntax
            "session.id": "sess-789".private(),
            "endpoint": "/api/v1/login".public(),
            "source": "mobile-app".public(),
        ]

        #expect(metadata.count == 8)
        #expect(metadata["user.id"]?.properties.privacyLevel == .private)
        #expect(metadata["action"]?.properties.privacyLevel == .public)
        #expect(metadata["timestamp"]?.properties.privacyLevel == .public)
        #expect(metadata["settings"]?.properties.privacyLevel == .private)
        #expect(metadata["features"]?.properties.privacyLevel == .public)
        #expect(metadata["session.id"]?.properties.privacyLevel == .private)
        #expect(metadata["endpoint"]?.properties.privacyLevel == .public)
        #expect(metadata["source"]?.properties.privacyLevel == .public)
    }

    @Test("Attributed metadata logging")
    func testAttributedMetadataLogging() {
        let handler = PrivacyTestLogHandler()
        var logger = Logger(label: "test") { _ in handler }
        logger.logLevel = .trace

        let attributedMetadata: Logger.AttributedMetadata = [
            "user.id": Logger.MetadataValue.string("12345").private(),
            "action": Logger.MetadataValue.string("login").public(),
        ]

        logger.log(level: .info, "User action", attributedMetadata: attributedMetadata)

        #expect(handler.messages.count == 1)
        #expect(handler.messages[0].level == .info)
        #expect(handler.messages[0].message.description == "User action")
        #expect(handler.messages[0].attributedMetadata != nil)
        #expect(handler.messages[0].attributedMetadata?["user.id"]?.properties.privacyLevel == .private)
        #expect(handler.messages[0].attributedMetadata?["action"]?.properties.privacyLevel == .public)
    }

    @Test("Global plain metadata is merged with attributed metadata as public")
    func testGlobalMetadataIsMergedWithAttributed() {
        let handler = PrivacyTestLogHandler()
        var logger = Logger(label: "test") { _ in handler }
        logger.logLevel = .trace

        // Set some global metadata via subscript
        logger[metadataKey: "service"] = "auth-service"
        logger[metadataKey: "version"] = "1.0"

        // Log with specific attributed metadata
        logger.log(
            level: .info,
            "Processing request",
            attributedMetadata: [
                "request.id": Logger.MetadataValue.string("req-123").public(),
                "user.id": Logger.MetadataValue.string("user-456").private(),
            ]
        )

        #expect(handler.messages.count == 1)

        let finalMetadata = handler.messages[0].attributedMetadata
        #expect(finalMetadata != nil)

        // Global metadata SHOULD be present in attributed logging, converted to public
        #expect(finalMetadata?["service"]?.properties.privacyLevel == .public)
        #expect(finalMetadata?["service"]?.value.description == "auth-service")
        #expect(finalMetadata?["version"]?.properties.privacyLevel == .public)
        #expect(finalMetadata?["version"]?.value.description == "1.0")

        // Log-specific metadata should also be present with their specified privacy levels
        #expect(finalMetadata?["request.id"]?.properties.privacyLevel == .public)
        #expect(finalMetadata?["user.id"]?.properties.privacyLevel == .private)
        #expect(finalMetadata?.count == 4)
    }

    @Test("Plain metadata and attributed metadata are separate paths")
    func testPlainAndAttributedSeparatePaths() {
        let handler = PrivacyTestLogHandler()
        var logger = Logger(label: "test") { _ in handler }
        logger.logLevel = .trace

        // Plain metadata logging should call the plain handler method
        logger.info(
            "Plain logging",
            metadata: [
                "key1": "value1",
                "key2": "value2",
            ]
        )

        #expect(handler.messages.count == 1)

        // Should receive plain metadata, not attributed
        #expect(handler.messages[0].metadata != nil)
        #expect(handler.messages[0].attributedMetadata == nil)
        #expect(handler.messages[0].metadata?["key1"]?.description == "value1")
        #expect(handler.messages[0].metadata?["key2"]?.description == "value2")
    }

    @Test("Default handler implementation filters private metadata")
    func testDefaultHandlerFiltersPrivateMetadata() {
        // Test the default LogHandler extension that filters private metadata
        let handler = FilterTestLogHandler()

        let attributedMetadata: Logger.AttributedMetadata = [
            "public_key": Logger.MetadataValue.string("public_value").public(),
            "private_key": Logger.MetadataValue.string("private_value").private(),
            "another_public": Logger.MetadataValue.string("another_public_value").public(),
        ]

        handler.log(
            level: .info,
            message: "Test message",
            attributedMetadata: attributedMetadata,
            source: "test",
            file: "test.swift",
            function: "testFunc",
            line: 42
        )

        // Only public metadata should reach the plain handler
        #expect(handler.receivedMetadata != nil)
        #expect(handler.receivedMetadata?.count == 2)
        #expect(handler.receivedMetadata?["public_key"]?.description == "public_value")
        #expect(handler.receivedMetadata?["another_public"]?.description == "another_public_value")
        #expect(handler.receivedMetadata?["private_key"] == nil)
    }

    @Test("PrivacyAwareStreamLogHandler redacts private metadata")
    func testPrivacyAwareStreamLogHandlerRedaction() {
        // Create a custom output stream to capture log output
        let stream = TestOutputStream()

        let handler = PrivacyAwareStreamLogHandler(
            label: "test",
            stream: stream,
            metadataProvider: nil
        )

        var logger = Logger(label: "test") { _ in handler }
        logger.privacyBehavior = .redact

        logger.log(
            level: .info,
            "User action",
            attributedMetadata: [
                "user.id": "12345".private(),
                "action": "login".public(),
                "session.id": "sess-789".private(),
            ]
        )

        // Check that private values are redacted as ***
        #expect(stream.output.contains("action=login"))
        #expect(stream.output.contains("user.id=***"))
        #expect(stream.output.contains("session.id=***"))
        #expect(!stream.output.contains("12345"))
        #expect(!stream.output.contains("sess-789"))
    }

    @Test("PrivacyAwareStreamLogHandler logs private metadata when configured")
    func testPrivacyAwareStreamLogHandlerLogsPrivate() {
        let stream = TestOutputStream()

        let handler = PrivacyAwareStreamLogHandler(
            label: "test",
            stream: stream,
            metadataProvider: nil
        )

        var logger = Logger(label: "test") { _ in handler }
        logger.privacyBehavior = .log

        logger.log(
            level: .info,
            "User action",
            attributedMetadata: [
                "user.id": "12345".private(),
                "action": "login".public(),
            ]
        )

        // Check that private values are logged normally
        #expect(stream.output.contains("user.id=12345"))
        #expect(stream.output.contains("action=login"))
        #expect(!stream.output.contains("***"))
    }

    @Test("PrivacyAwareStreamLogHandler factory methods work")
    func testPrivacyAwareStreamLogHandlerFactoryMethods() {
        // Test stdout factory with default
        let stdoutHandler = PrivacyAwareStreamLogHandler.standardOutput(label: "stdout-test")
        #expect(stdoutHandler.logLevel == .info)
        #expect(stdoutHandler.privacyBehavior == .redact)

        // Test stderr factory
        let stderrHandler = PrivacyAwareStreamLogHandler.standardError(label: "stderr-test")
        #expect(stderrHandler.logLevel == .info)
        #expect(stderrHandler.privacyBehavior == .redact)

        // Test with metadata provider
        let provider = Logger.MetadataProvider { ["env": "test"] }
        let handlerWithProvider = PrivacyAwareStreamLogHandler.standardOutput(
            label: "test",
            metadataProvider: provider
        )
        #expect(handlerWithProvider.metadataProvider != nil)
        #expect(handlerWithProvider.privacyBehavior == .redact)
    }

    @Test("PrivacyAwareStreamLogHandler handles plain metadata")
    func testPrivacyAwareStreamLogHandlerPlainMetadata() {
        let stream = TestOutputStream()

        let handler = PrivacyAwareStreamLogHandler(
            label: "test",
            stream: stream,
            metadataProvider: nil
        )

        let logger = Logger(label: "test") { _ in handler }

        // Plain metadata should work normally
        logger.info("Plain message", metadata: ["key": "value", "count": "42"])

        #expect(stream.output.contains("key=value"))
        #expect(stream.output.contains("count=42"))
    }

    @Test("PrivacyAwareStreamLogHandler merges global metadata")
    func testPrivacyAwareStreamLogHandlerGlobalMetadata() {
        let stream = TestOutputStream()

        let handler = PrivacyAwareStreamLogHandler(
            label: "test",
            stream: stream,
            metadataProvider: nil
        )

        var logger = Logger(label: "test") { _ in handler }
        logger[metadataKey: "service"] = "auth"
        logger[metadataKey: "version"] = "1.0"
        logger.privacyBehavior = .redact

        logger.log(
            level: .info,
            "Request",
            attributedMetadata: [
                "user.id": "123".private(),
                "request.id": "req-456".public(),
            ]
        )

        // Global metadata should appear (treated as public)
        #expect(stream.output.contains("service=auth"))
        #expect(stream.output.contains("version=1.0"))
        // Public attributed metadata should appear
        #expect(stream.output.contains("request.id=req-456"))
        // Private attributed metadata should be redacted
        #expect(stream.output.contains("user.id=***"))
        #expect(!stream.output.contains("123"))
    }

    @Test("PrivacyBehavior enum properties")
    func testPrivacyBehavior() {
        #expect(Logger.PrivacyBehavior.log.rawValue == "log")
        #expect(Logger.PrivacyBehavior.redact.rawValue == "redact")
        #expect(Logger.PrivacyBehavior.allCases.contains(.log))
        #expect(Logger.PrivacyBehavior.allCases.contains(.redact))
        #expect(Logger.PrivacyBehavior.allCases.count == 2)
    }

    @Test("Logger privacyBehavior property")
    func testLoggerPrivacyBehavior() {
        let handler = PrivacyAwareStreamLogHandler.standardOutput(label: "test")
        var logger = Logger(label: "test") { _ in handler }

        // Default should be .redact
        #expect(logger.privacyBehavior == .redact)

        // Should be able to change it
        logger.privacyBehavior = .log
        #expect(logger.privacyBehavior == .log)

        // Should support value semantics (COW)
        var logger2 = logger
        logger2.privacyBehavior = .redact
        #expect(logger.privacyBehavior == .log)
        #expect(logger2.privacyBehavior == .redact)
    }
}

// MARK: - Test Helpers

/// Test output stream for capturing log output
internal final class TestOutputStream: TextOutputStream, @unchecked Sendable {
    var output: String = ""

    func write(_ string: String) {
        // This is a test implementation, a real implementation would include locking
        self.output += string
    }
}

internal final class PrivacyTestLogHandler: LogHandler {
    var logLevel: Logger.Level = .trace
    var metadata: Logger.Metadata = [:]
    var metadataProvider: Logger.MetadataProvider?
    var messages:
        [(
            level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?,
            attributedMetadata: Logger.AttributedMetadata?
        )] = []

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        self.messages.append((level: level, message: message, metadata: metadata, attributedMetadata: nil))
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        attributedMetadata: Logger.AttributedMetadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Merge handler metadata, provider metadata, and explicit attributed metadata
        var merged = Logger.AttributedMetadata()

        // Add handler metadata as public
        for (key, value) in self.metadata {
            merged[key] = Logger.AttributedMetadataValue(value, privacy: .public)
        }

        // Add metadata provider values as public
        if let provider = self.metadataProvider {
            for (key, value) in provider.get() {
                merged[key] = Logger.AttributedMetadataValue(value, privacy: .public)
            }
        }

        // Merge with explicit attributed metadata (takes precedence)
        if let attributedMetadata = attributedMetadata {
            for (key, value) in attributedMetadata {
                merged[key] = value
            }
        }

        self.messages.append((level: level, message: message, metadata: nil, attributedMetadata: merged.isEmpty ? nil : merged))
    }

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }
}

/// LogHandler that doesn't implement attributed method, relying on default implementation
internal final class FilterTestLogHandler: LogHandler {
    var logLevel: Logger.Level = .trace
    var metadata: Logger.Metadata = [:]
    var metadataProvider: Logger.MetadataProvider?
    var receivedMetadata: Logger.Metadata?

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        self.receivedMetadata = metadata
    }

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }
}
