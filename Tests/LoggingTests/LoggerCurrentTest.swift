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

/// Tests for SLG-0008: default ``Logger/current``. Most behaviour is inherited from
/// SLG-0006's extension on `TaskLocal where Value == Logger`; this suite covers what's
/// specific to the default instance.
struct LoggerCurrentTest {
    @Test func defaultLabelIsEmpty() {
        // Outside any withValue, the default Logger has the empty label.
        #expect(Logger.current.wrappedValue.label == "")
    }

    @Test func currentSurvivesWithMetadataScope() {
        Logger.current.withMetadata(merging: ["k": "v"]) {
            #expect(Logger.current.wrappedValue[metadataKey: "k"] == "v")
        }
        // After the scope, the binding is restored.
        #expect(Logger.current.wrappedValue[metadataKey: "k"] == nil)
    }

    @Test func emitsThroughCurrent() {
        let logging = TestLogging()
        let bound = Logger(label: "app", factory: { logging.make(label: $0) })
        Logger.current.withValue(bound) {
            Logger.current.withMetadata(merging: ["request.id": "r1"]) {
                Logger.current.info("via current")
            }
        }
        logging.history.assertExist(
            level: .info,
            message: "via current",
            metadata: ["request.id": "r1"]
        )
    }

    @Test func nestedCurrentScopesAccumulate() {
        let logging = TestLogging()
        let bound = Logger(label: "app", factory: { logging.make(label: $0) })
        Logger.current.withValue(bound) {
            Logger.current.withMetadata(merging: ["a": "1"]) {
                Logger.current.withMetadata(merging: ["b": "2"]) {
                    Logger.current.info("both")
                }
            }
        }
        logging.history.assertExist(
            level: .info,
            message: "both",
            metadata: ["a": "1", "b": "2"]
        )
    }

    @Test func currentDoesNotInherentInDetached() async {
        await Logger.current.withMetadata(merging: ["k": "v"]) {
            await Task.detached {
                // Detached tasks don't inherit task-locals.
                #expect(Logger.current.wrappedValue[metadataKey: "k"] == nil)
            }.value
        }
    }
}
