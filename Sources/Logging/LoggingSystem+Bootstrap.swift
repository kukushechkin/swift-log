//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Logging API open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift Logging API project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Logging API project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

extension LoggingSystem {
    /// The factory used to create a ``LogHandler`` before any explicit ``bootstrap(_:)`` call is made.
    static let defaultLogHandlerFactory: @Sendable (String, Logger.MetadataProvider?) -> any LogHandler = {
        label,
        _ in
        StreamLogHandler.standardError(label: label)
    }

    /// A one-time configuration function that globally selects the implementation for your desired logging backend.
    ///
    /// >  Warning:
    /// > `bootstrap` can be called at maximum once in any given program, calling it more than once will
    /// > lead to undefined behavior, most likely a crash.
    ///
    /// - parameters:
    ///     - factory: A closure that provides a ``Logger`` label identifier and produces an instance of the ``LogHandler``.
    @preconcurrency
    public static func bootstrap(_ factory: @escaping @Sendable (String) -> any LogHandler) {
        self._factory.replace(
            { label, _ in
                factory(label)
            },
            validate: true
        )
    }

    /// A one-time configuration function that globally selects the implementation for your desired logging backend.
    ///
    /// >  Warning:
    /// > `bootstrap` can be called at maximum once in any given program, calling it more than once will
    /// > lead to undefined behavior, most likely a crash.
    ///
    /// - parameters:
    ///     - metadataProvider: The `MetadataProvider` used to inject runtime-generated metadata from the execution context.
    ///     - factory: A closure that provides a ``Logger`` label identifier and produces an instance of the ``LogHandler``.
    @preconcurrency
    public static func bootstrap(
        _ factory: @escaping @Sendable (String, Logger.MetadataProvider?) -> any LogHandler,
        metadataProvider: Logger.MetadataProvider?
    ) {
        self._metadataProviderFactory.replace(metadataProvider, validate: true)
        self._factory.replace(factory, validate: true)
    }

    // for our testing we want to allow multiple bootstrapping
    internal static func bootstrapInternal(_ factory: @escaping @Sendable (String) -> any LogHandler) {
        self._metadataProviderFactory.replace(nil, validate: false)
        self._factory.replace(
            { label, _ in
                factory(label)
            },
            validate: false
        )
    }

    // for our testing we want to allow multiple bootstrapping
    internal static func bootstrapInternal(
        _ factory: @escaping @Sendable (String, Logger.MetadataProvider?) -> any LogHandler,
        metadataProvider: Logger.MetadataProvider?
    ) {
        self._metadataProviderFactory.replace(metadataProvider, validate: false)
        self._factory.replace(factory, validate: false)
    }
}
