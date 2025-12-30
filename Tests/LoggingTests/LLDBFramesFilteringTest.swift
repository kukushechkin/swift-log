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

actor GlobalLoggerContext {
    /// MARK: - task local logger

    @TaskLocal
    static var taskLocalLogger = Logger(label: "TaskLocalPlaygroundLogger_global")

    @inline(__always)
    static func withTaskLocalLoggerInline(metadata: Logger.Metadata, _ body: (Logger) -> Void) {
        let newLogger = self.taskLocalLogger.with(additionalMetadata: metadata)
        self.$taskLocalLogger.withValue(newLogger) {
            body(self.taskLocalLogger)
        }
    }
}

struct LLDBFramesFilteringTest {    
    @inline(never)
    fileprivate func someRecursiveFunc(_ i: Int = 100) {
        if i == 0 {
            return
        }
        let additionalMetadata: Logger.Metadata = [
            "iteration-\(i)-key1": "iteration-\(i)-value1"
        ]
        GlobalLoggerContext.withTaskLocalLoggerInline(metadata: additionalMetadata) { logger in
            someRecursiveFunc(i - 1)
        }
    }
    
    @Test
    func testLongStack() {
        someRecursiveFunc()
    }
}
