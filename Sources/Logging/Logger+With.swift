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

extension Logger {
    /// Create a new logger with additional metadata merged into the existing metadata.
    ///
    /// This method merges the provided metadata with the logger's current metadata,
    /// returning a new logger instance. The original logger is not modified.
    /// This method is more efficient than setting metadata items individually in a loop,
    /// as it triggers copy-on-write only once.
    ///
    /// - Parameter additionalMetadata: The metadata dictionary to merge. Values in `additionalMetadata`
    ///   will override existing values for the same keys.
    /// - Returns: A new `Logger` instance with the merged metadata.
    @inlinable
    public func with(additionalMetadata: Logger.Metadata) -> Logger {
        var newLogger = self
        if additionalMetadata.count == 1 {
            newLogger.handler.metadata[additionalMetadata.first!.key] = additionalMetadata.first!.value
        } else {
            newLogger.handler.metadata.merge(additionalMetadata) { _, new in new }
        }
        return newLogger
    }

    /// Execute a closure with a logger that has additional metadata merged in.
    ///
    /// This method efficiently creates a new logger with merged metadata and passes it to the closure,
    /// providing a structured way to scope logger modifications.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge. Values in `additionalMetadata`
    ///     will override existing values for the same keys.
    ///   - body: The closure to execute with the modified logger.
    @inlinable
    public func with(
        additionalMetadata: Logger.Metadata,
        _ body: (Logger) -> Void
    ) {
        body(self.with(additionalMetadata: additionalMetadata))
    }

    /// Create a new logger with a different log level.
    ///
    /// This method returns a new logger instance with the specified log level.
    /// The original logger is not modified.
    ///
    /// - Parameter logLevel: The log level to set on the new logger.
    /// - Returns: A new `Logger` instance with the specified log level.
    @inlinable
    public func with(logLevel: Logger.Level) -> Logger {
        var newLogger = self
        newLogger.logLevel = logLevel
        return newLogger
    }

    /// Execute a closure with a logger that has a different log level.
    ///
    /// This method efficiently creates a new logger with the specified log level and passes it to the closure,
    /// providing a structured way to scope logger modifications.
    ///
    /// - Parameters:
    ///   - logLevel: The log level to set on the new logger.
    ///   - body: The closure to execute with the modified logger.
    @inlinable
    public func with(
        logLevel: Logger.Level,
        _ body: (Logger) -> Void
    ) {
        body(self.with(logLevel: logLevel))
    }

    /// Create a new logger with a different log handler.
    ///
    /// This method returns a new logger instance with the specified log handler.
    /// The original logger is not modified.
    ///
    /// - Parameter handler: The log handler to use for the new logger.
    /// - Returns: A new `Logger` instance with the specified handler.
    @inlinable
    public func with(handler: any LogHandler) -> Logger {
        var newLogger = self
        newLogger.handler = handler
        return newLogger
    }

    /// Execute a closure with a logger that has a different log handler.
    ///
    /// This method efficiently creates a new logger with the specified handler and passes it to the closure,
    /// providing a structured way to scope logger modifications. After the closure completes, the handler
    /// is returned, allowing inspection of any state changes (e.g., examining logs captured by an in-memory handler).
    ///
    /// - Parameters:
    ///   - handler: The log handler to use for the new logger.
    ///   - body: The closure to execute with the modified logger.
    /// - Returns: The log handler after the closure has executed, allowing inspection of its state.
    @inlinable
    public func with(
        handler: any LogHandler,
        _ body: (Logger) -> Void
    ) -> any LogHandler {
        let newLogger = self.with(handler: handler)
        body(newLogger)
        return newLogger.handler
    }

    /// Create a new logger with additional metadata and a different log level.
    ///
    /// This method efficiently applies both modifications in a single copy-on-write operation.
    /// The original logger is not modified.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with existing metadata.
    ///   - logLevel: The log level to set on the new logger.
    /// - Returns: A new `Logger` instance with the specified modifications.
    @inlinable
    public func with(additionalMetadata: Logger.Metadata, logLevel: Logger.Level) -> Logger {
        var newLogger = self
        if additionalMetadata.count == 1 {
            newLogger.handler.metadata[additionalMetadata.first!.key] = additionalMetadata.first!.value
        } else {
            newLogger.handler.metadata.merge(additionalMetadata) { _, new in new }
        }
        newLogger.logLevel = logLevel
        return newLogger
    }

    /// Execute a closure with a logger that has additional metadata and a different log level.
    ///
    /// This method efficiently creates a new logger with both modifications and passes it to the closure,
    /// providing a structured way to scope logger modifications.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with existing metadata.
    ///   - logLevel: The log level to set on the new logger.
    ///   - body: The closure to execute with the modified logger.
    @inlinable
    public func with(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        _ body: (Logger) -> Void
    ) {
        body(self.with(additionalMetadata: additionalMetadata, logLevel: logLevel))
    }

    /// Create a new logger with additional metadata and a different log handler.
    ///
    /// This method efficiently applies both modifications in a single copy-on-write operation.
    /// The original logger is not modified.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with existing metadata.
    ///   - handler: The log handler to use for the new logger.
    /// - Returns: A new `Logger` instance with the specified modifications.
    @inlinable
    public func with(additionalMetadata: Logger.Metadata, handler: any LogHandler) -> Logger {
        var newLogger = self
        var newHandler = handler
        if additionalMetadata.count == 1 {
            newHandler.metadata[additionalMetadata.first!.key] = additionalMetadata.first!.value
        } else {
            newHandler.metadata.merge(additionalMetadata) { _, new in new }
        }
        newLogger.handler = newHandler
        return newLogger
    }

    /// Execute a closure with a logger that has additional metadata and a different log handler.
    ///
    /// This method efficiently creates a new logger with both modifications and passes it to the closure,
    /// providing a structured way to scope logger modifications. After the closure completes, the handler
    /// is returned, allowing inspection of any state changes (e.g., examining logs captured by an in-memory handler).
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with existing metadata.
    ///   - handler: The log handler to use for the new logger.
    ///   - body: The closure to execute with the modified logger.
    /// - Returns: The log handler after the closure has executed, allowing inspection of its state.
    @inlinable
    public func with(
        additionalMetadata: Logger.Metadata,
        handler: any LogHandler,
        _ body: (Logger) -> Void
    ) -> any LogHandler {
        let newLogger = self.with(additionalMetadata: additionalMetadata, handler: handler)
        body(newLogger)
        return newLogger.handler
    }

    /// Create a new logger with a different log level and log handler.
    ///
    /// This method efficiently applies both modifications in a single copy-on-write operation.
    /// The original logger is not modified.
    ///
    /// - Parameters:
    ///   - logLevel: The log level to set on the new logger.
    ///   - handler: The log handler to use for the new logger.
    /// - Returns: A new `Logger` instance with the specified modifications.
    @inlinable
    public func with(logLevel: Logger.Level, handler: any LogHandler) -> Logger {
        var newLogger = self
        var newHandler = handler
        newHandler.logLevel = logLevel
        newLogger.handler = newHandler
        return newLogger
    }

    /// Execute a closure with a logger that has a different log level and log handler.
    ///
    /// This method efficiently creates a new logger with both modifications and passes it to the closure,
    /// providing a structured way to scope logger modifications. After the closure completes, the handler
    /// is returned, allowing inspection of any state changes (e.g., examining logs captured by an in-memory handler).
    ///
    /// - Parameters:
    ///   - logLevel: The log level to set on the new logger.
    ///   - handler: The log handler to use for the new logger.
    ///   - body: The closure to execute with the modified logger.
    /// - Returns: The log handler after the closure has executed, allowing inspection of its state.
    @inlinable
    public func with(
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) -> Void
    ) -> any LogHandler {
        let newLogger = self.with(logLevel: logLevel, handler: handler)
        body(newLogger)
        return newLogger.handler
    }

    /// Create a new logger with additional metadata, a different log level, and a different log handler.
    ///
    /// This method efficiently applies all three modifications in a single copy-on-write operation.
    /// The original logger is not modified.
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with existing metadata.
    ///   - logLevel: The log level to set on the new logger.
    ///   - handler: The log handler to use for the new logger.
    /// - Returns: A new `Logger` instance with the specified modifications.
    @inlinable
    public func with(additionalMetadata: Logger.Metadata, logLevel: Logger.Level, handler: any LogHandler) -> Logger {
        var newLogger = self
        var newHandler = handler
        if additionalMetadata.count == 1 {
            newHandler.metadata[additionalMetadata.first!.key] = additionalMetadata.first!.value
        } else {
            newHandler.metadata.merge(additionalMetadata) { _, new in new }
        }
        newHandler.logLevel = logLevel
        newLogger.handler = newHandler
        return newLogger
    }

    /// Execute a closure with a logger that has additional metadata, a different log level, and a different log handler.
    ///
    /// This method efficiently creates a new logger with all three modifications and passes it to the closure,
    /// providing a structured way to scope logger modifications. After the closure completes, the handler
    /// is returned, allowing inspection of any state changes (e.g., examining logs captured by an in-memory handler).
    ///
    /// - Parameters:
    ///   - additionalMetadata: The metadata dictionary to merge with existing metadata.
    ///   - logLevel: The log level to set on the new logger.
    ///   - handler: The log handler to use for the new logger.
    ///   - body: The closure to execute with the modified logger.
    /// - Returns: The log handler after the closure has executed, allowing inspection of its state.
    @inlinable
    public func with(
        additionalMetadata: Logger.Metadata,
        logLevel: Logger.Level,
        handler: any LogHandler,
        _ body: (Logger) -> Void
    ) -> any LogHandler {
        let newLogger = self.with(additionalMetadata: additionalMetadata, logLevel: logLevel, handler: handler)
        body(newLogger)
        return newLogger.handler
    }
}
