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

#if canImport(os)
public import Logging
import LoggingAttributes
import os

/// A redaction-aware log handler that uses Apple's unified logging system (os.Logger).
///
/// This handler leverages OSLog's native privacy support to automatically redact
/// metadata values marked with `.sensitive` when viewing logs outside of
/// development environments.
///
/// ## Features
///
/// - **Native Privacy Support**: Uses OSLog's `privacy: .private` and `privacy: .public` annotations
/// - **System Integration**: Logs appear in Console.app and can be viewed with `log` command
/// - **Performance**: Zero-cost when logging is disabled at the system level
/// - **Subsystem Organization**: Groups logs by subsystem and category for better filtering
///
/// ## Usage
///
/// ```swift
/// let handler = OSLogHandler(subsystem: "com.example.myapp", category: "network")
/// let logger = Logger(label: "network") { _ in handler }
///
/// let userId = "12345"
/// logger.info("User logged in", metadata: [
///     "user.id": "\(userId, sensitivity: .sensitive)",
///     "action": "\(\"login\", sensitivity: .public)"
/// ])
/// ```
///
/// ## Redaction Behavior
///
/// - `.sensitive` metadata -> OSLog `privacy: .private` (redacted as `<private>` in logs)
/// - `.public` metadata -> OSLog `privacy: .public` (always visible)
/// - Plain metadata -> Treated as `.public` by default
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public struct OSLogHandler: LogHandler {
    private var osLogger: os.Logger

    public var metadata: Logging.Logger.Metadata = [:]
    public var metadataProvider: Logging.Logger.MetadataProvider?
    public var logLevel: Logging.Logger.Level = .info

    /// Controls whether to append a suffix listing redacted keys.
    public var showRedactedKeysList: Bool = true

    /// Creates an OSLog handler with the specified subsystem and category.
    public init(subsystem: String, category: String) {
        self.osLogger = os.Logger(subsystem: subsystem, category: category)
    }

    public func log(event: LogEvent) {
        var merged = self.metadata

        if let provider = self.metadataProvider {
            let provided = provider.get()
            merged.merge(provided, uniquingKeysWith: { _, rhs in rhs })
        }

        if let eventMetadata = event.metadata {
            merged.merge(eventMetadata, uniquingKeysWith: { _, rhs in rhs })
        }

        if let error = event.error {
            if merged["error.message"] == nil {
                merged["error.message"] = "\(error)"
            }
            if merged["error.type"] == nil {
                merged["error.type"] = "\(String(reflecting: type(of: error)))"
            }
        }

        if merged.isEmpty {
            self.osLogger.log(level: self.mapLogLevel(event.level), "\(event.message.description)")
        } else if merged.contains(where: { $0.value.attributes.sensitivity == .sensitive }) {
            self.logToOSLogWithRedaction(level: event.level, message: event.message, metadata: merged)
        } else {
            let metadataString = merged.sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            self.osLogger.log(
                level: self.mapLogLevel(event.level),
                "\(event.message.description) \(metadataString, privacy: .public)"
            )
        }
    }

    public subscript(metadataKey key: String) -> Logging.Logger.Metadata.Value? {
        get { self.metadata[key] }
        set { self.metadata[key] = newValue }
    }

    // MARK: - Private Helpers

    private func logToOSLogWithRedaction(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata: Logging.Logger.Metadata
    ) {
        let osLogType = self.mapLogLevel(level)

        let publicMetadata = metadata.filter { $0.value.attributes.sensitivity != .sensitive }
        let redactedMetadata = metadata.filter { $0.value.attributes.sensitivity == .sensitive }

        let redactedKeysSuffix = self.showRedactedKeysList ? self.formatRedactedKeysSuffix(redactedMetadata) : ""

        let publicString = self.formatMetadataValues(publicMetadata)
        let redactedString = self.formatMetadataValues(redactedMetadata)

        switch (!publicString.isEmpty, !redactedString.isEmpty) {
        case (true, true):
            self.osLogger.log(
                level: osLogType,
                "\(message.description) \(publicString, privacy: .public) \(redactedString, privacy: .private)\(redactedKeysSuffix, privacy: .public)"
            )
        case (true, false):
            self.osLogger.log(level: osLogType, "\(message.description) \(publicString, privacy: .public)")
        case (false, true):
            self.osLogger.log(
                level: osLogType,
                "\(message.description) \(redactedString, privacy: .private)\(redactedKeysSuffix, privacy: .public)"
            )
        case (false, false):
            self.osLogger.log(level: osLogType, "\(message.description)")
        }
    }

    private func mapLogLevel(_ level: Logging.Logger.Level) -> OSLogType {
        switch level {
        case .trace: return .debug
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning: return .error
        case .error: return .error
        case .critical: return .fault
        }
    }

    private func formatMetadataValues(_ metadata: Logging.Logger.Metadata) -> String {
        metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }

    private func formatRedactedKeysSuffix(_ metadata: Logging.Logger.Metadata) -> String {
        if metadata.isEmpty { return "" }
        let keys = metadata.keys.sorted().joined(separator: ", ")
        let keyWord = metadata.count == 1 ? "key" : "keys"
        let isWord = metadata.count == 1 ? "is" : "are"
        return " (\(keyWord) \(keys) \(isWord) marked private)"
    }
}

#endif
