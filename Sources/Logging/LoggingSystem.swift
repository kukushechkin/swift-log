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

/// The logging system is a global facility where you can configure the default logging backend implementation.
///
/// `LoggingSystem` is set up just once in a given program to set up the desired logging backend implementation.
/// The default behavior, if you don't define otherwise, sets the ``LogHandler`` to use a ``StreamLogHandler`` that presents its output to `STDOUT`.
///
/// You can configure that handler to present the output to `STDERR` instead using the following code:
///
/// ```swift
/// LoggingSystem.bootstrap(StreamLogHandler.standardError)
/// ```
///
/// The default (``StreamLogHandler``) is intended to be a convenience.
/// For production applications, implement the ``LogHandler`` protocol directly, or use a community-maintained backend.
public enum LoggingSystem: Sendable {
    internal static let _factory = FactoryBox(
        defaultLogHandlerFactory,
        violationErrorMesage: "logging system can only be initialized once per process."
    )
    internal static let _metadataProviderFactory = MetadataProviderBox(
        nil,
        violationErrorMesage: "logging system can only be initialized once per process."
    )

    #if DEBUG
    private static let _warnOnceBox: WarnOnceBox = WarnOnceBox()
    #endif

    internal static var factory: (String, Logger.MetadataProvider?) -> any LogHandler {
        { label, metadataProvider in
            self._factory.underlying(label, metadataProvider)
        }
    }

    /// System wide ``Logger/MetadataProvider`` that was configured during the logging system's `bootstrap`.
    ///
    /// When creating a ``Logger`` using the plain ``Logger/init(label:)`` initializer, this metadata provider
    /// will be provided to it.
    ///
    /// When using custom log handler factories, make sure to provide the bootstrapped metadata provider to them,
    /// or the metadata will not be filled in automatically using the provider on log-sites. While using a custom
    /// factory to avoid using the bootstrapped metadata provider may sometimes be useful, usually it will lead to
    /// un-expected behavior, so make sure to always propagate it to your handlers.
    public static var metadataProvider: Logger.MetadataProvider? {
        self._metadataProviderFactory.underlying
    }

    #if DEBUG
    /// Used to warn only once about a specific ``LogHandler`` type when it does not support ``Logger/MetadataProvider``,
    /// but an attempt was made to set a metadata provider on such handler. In order to avoid flooding the system with
    /// warnings such warning is only emitted in debug mode, and even then at-most once for a handler type.
    internal static func warnOnceLogHandlerNotSupportedMetadataProvider<Handler: LogHandler>(
        _ type: Handler.Type
    ) -> Bool {
        self._warnOnceBox.warnOnceLogHandlerNotSupportedMetadataProvider(type: type)
    }
    #endif

    /// Protects an object such that it can only be accessed through a Reader-Writer lock.
    final class RWLockedValueBox<Value: Sendable>: @unchecked Sendable {
        private let lock = ReadWriteLock()
        private var storage: Value

        init(initialValue: Value) {
            self.storage = initialValue
        }

        func withReadLock<Result>(_ operation: (Value) -> Result) -> Result {
            self.lock.withReaderLock {
                operation(self.storage)
            }
        }

        func withWriteLock<Result>(_ operation: (inout Value) -> Result) -> Result {
            self.lock.withWriterLock {
                operation(&self.storage)
            }
        }
    }

    /// Protects an object by applying the constraints that it can only be accessed through a Reader-Writer lock
    /// and can only be updated once from the initial value given.
    internal struct ReplaceOnceBox<BoxedType: Sendable> {
        private struct ReplaceOnce: Sendable {
            private(set) var initialized = false
            private var _underlying: BoxedType
            private let violationErrorMessage: String

            mutating func replaceUnderlying(_ underlying: BoxedType, validate: Bool) {
                precondition(!validate || !self.initialized, self.violationErrorMessage)
                self._underlying = underlying
                self.initialized = true
            }

            var underlying: BoxedType {
                self._underlying
            }

            init(underlying: BoxedType, violationErrorMessage: String) {
                self._underlying = underlying
                self.violationErrorMessage = violationErrorMessage
            }
        }

        private let storage: RWLockedValueBox<ReplaceOnce>

        init(_ underlying: BoxedType, violationErrorMesage: String) {
            self.storage = .init(
                initialValue: ReplaceOnce(
                    underlying: underlying,
                    violationErrorMessage: violationErrorMesage
                )
            )
        }

        func replace(_ newUnderlying: BoxedType, validate: Bool) {
            self.storage.withWriteLock { $0.replaceUnderlying(newUnderlying, validate: validate) }
        }

        var underlying: BoxedType {
            self.storage.withReadLock { $0.underlying }
        }

        var isInitialized: Bool {
            self.storage.withReadLock { $0.initialized }
        }
    }

    internal typealias FactoryBox = ReplaceOnceBox<
        @Sendable (_ label: String, _ provider: Logger.MetadataProvider?) -> any LogHandler
    >

    internal typealias MetadataProviderBox = ReplaceOnceBox<Logger.MetadataProvider?>
}

// MARK: - Debug only warnings

#if DEBUG
/// Contains state to manage all kinds of "warn only once" warnings which the logging system may want to issue.
private final class WarnOnceBox: @unchecked Sendable {
    private let lock: Lock = Lock()
    private var warnOnceLogHandlerNotSupportedMetadataProviderPerType = Set<ObjectIdentifier>()

    func warnOnceLogHandlerNotSupportedMetadataProvider<Handler: LogHandler>(type: Handler.Type) -> Bool {
        self.lock.withLock {
            let id = ObjectIdentifier(type)
            let (inserted, _) = warnOnceLogHandlerNotSupportedMetadataProviderPerType.insert(id)
            return inserted  // warn about this handler type, it is the first time we encountered it
        }
    }
}
#endif
