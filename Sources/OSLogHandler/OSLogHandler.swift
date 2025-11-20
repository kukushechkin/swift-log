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

import OSLog
import Logging

/// Extension to allow Logger.Metadata to be used in OSLog string interpolation
@available(macOS 11, *)
extension OSLogInterpolation {
    @inlinable
    mutating func appendInterpolation(
        _ metadata: Logging.Logger.Metadata,
        privacy: OSLogPrivacy = .auto
    ) {
        guard !metadata.isEmpty else { return }

        appendLiteral("[")
        for (index, (key, value)) in metadata.enumerated() {
            if index > 0 {
                appendLiteral(" ")
            }
            
            // TODO: this decision should be based on the `value` privacy label instead
            if key.starts(with: "public_") {
                appendInterpolation(key, privacy: .public)
            } else {
                appendInterpolation(key, privacy: .private)
            }
            appendLiteral("=")
            appendInterpolation(value)
        }
        appendLiteral("]")
    }

    /// Appends a metadata value with privacy control
    @inlinable
    mutating func appendInterpolation(_ value: Logging.Logger.Metadata.Value) {
        switch value {
        case .string(let str, let privacyLevel):
            if privacyLevel == .public {
                appendInterpolation(str, privacy: .public)
            } else {
                appendInterpolation(str, privacy: .private)
            }
        case .stringConvertible(let convertible, let privacyLevel):
            if privacyLevel == .public {
                appendInterpolation(convertible.description, privacy: .public)
            } else {
                appendInterpolation(convertible.description, privacy: .private)
            }
        case .array(let array, let privacyLevel):
            let formatted = "[\(array.map { stringify($0) }.joined(separator: ", "))]"
            if privacyLevel == .public {
                appendInterpolation(formatted, privacy: .public)
            } else {
                appendInterpolation(formatted, privacy: .private)
            }
        case .dictionary(let dict, let privacyLevel):
            let formatted = "{\(dict.map { "\($0.key): \(stringify($0.value))" }.joined(separator: ", "))}"
            if privacyLevel == .public {
                appendInterpolation(formatted, privacy: .public)
            } else {
                appendInterpolation(formatted, privacy: .private)
            }
        }
    }

    @inlinable
    package func stringify(_ value: Logging.Logger.Metadata.Value) -> String {
        switch value {
        case .string(let str, _):
            return str
        case .stringConvertible(let convertible, _):
            return convertible.description
        case .array(let array, _):
            return "[\(array.map { stringify($0) }.joined(separator: ", "))]"
        case .dictionary(let dict, _):
            return "{\(dict.map { "\($0.key): \(stringify($0.value))" }.joined(separator: ", "))}"
        }
    }
}

@available(macOS 11, *)
struct OSLogHandler: LogHandler {
    let internalOSLog: os.Logger
    let subsystem: String
    let category: String
    public var metadataProvider: Logging.Logger.MetadataProvider?
    
    init(subsystem: String, category: String, metadataProvider: Logging.Logger.MetadataProvider?) {
        self.internalOSLog = os.Logger.init(subsystem: subsystem, category: category)
        self.subsystem = subsystem
        self.category = category
        self.metadataProvider = metadataProvider
    }

    init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        self.metadataProvider = LoggingSystem.metadataProvider
        self.internalOSLog = os.Logger.init(subsystem: subsystem, category: category)
    }

    func mapToOSLogLevel(_ level: Logging.Logger.Level) -> OSLogType {
        switch level {
        case .trace: return .default
        case .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        @unknown default: return OSLogType.default
        }
    }

    func log(
        level: Logging.Logger.Level,
        message: Logging.Logger.Message,
        metadata explicitMetadata: Logging.Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        // Merge metadata according to SwiftLog hierarchy
        var effectiveMetadata = self.metadata
        if let metadataProvider = self.metadataProvider {
            effectiveMetadata.merge(metadataProvider.get()) { _, new in new }
        }
        if let explicitMetadata = explicitMetadata {
            effectiveMetadata.merge(explicitMetadata) { _, new in new }
        }

        // Build OSLog message with per-metadata-value privacy controls
        if effectiveMetadata.isEmpty {
            self.internalOSLog.log(level: self.mapToOSLogLevel(level), "\(message, privacy: .public)")
        } else {
            self.internalOSLog.log(level: self.mapToOSLogLevel(level), "\(effectiveMetadata) \(message, privacy: .public)")
        }
    }

    private var _logLevel: Logging.Logger.Level?
    var logLevel: Logging.Logger.Level {
        get {
            self._logLevel ?? .debug
        }
        set {
            self._logLevel = newValue
        }
    }

    private var _metadataSet = false
    private var _metadata = Logging.Logger.Metadata() {
        didSet {
            self._metadataSet = true
        }
    }

    public var metadata: Logging.Logger.Metadata {
        get {
            self._metadata
        }
        set {
            self._metadata = newValue
        }
    }

    subscript(metadataKey metadataKey: Logging.Logger.Metadata.Key) -> Logging.Logger.Metadata.Value? {
        get {
            self._metadata[metadataKey]
        }
        set {
            self._metadata[metadataKey] = newValue
        }
    }
}
