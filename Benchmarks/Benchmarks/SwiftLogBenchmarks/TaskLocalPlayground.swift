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

import Benchmark
import Foundation
import Logging

actor GlobalLoggerContext {
    /// MARK: - task local logger

    @TaskLocal
    // static var taskLocalLogger = Logger(label: "TaskLocalPlaygroundLogger_global") { _ in
    //     NoOpLogHandler(label: "NoOpLogHandler_global")
    // }
    static var taskLocalLogger = Logger(label: "TaskLocalPlaygroundLogger_global")

    @inline(__always)
    static func withTaskLocalLoggerInline(metadata: Logger.Metadata, _ body: (Logger) -> Void) {
        var newLogger = self.taskLocalLogger
        for metadataValue in metadata {
            newLogger[metadataKey: metadataValue.0] = metadataValue.1
        }
        self.$taskLocalLogger.withValue(newLogger) {
            body(self.taskLocalLogger)
        }
    }
}

/// MARK: - payload functions

@inline(never)
func explicitLogger(logger: Logger, iterations: Int = 100) {
    if iterations == 0 {
        return
    }
    logger.info("I am a recursive function")
    var newLogger = logger
    newLogger[metadataKey: "iteration-\(iterations)-key"] = "iteration-\(iterations)-value"
    explicitLogger(logger: newLogger, iterations: iterations - 1)
    logger.info("I am done")
}

@inline(never)
func implicitLogger(iterations: Int = 100) {
    if iterations == 0 {
        return
    }
    GlobalLoggerContext.withTaskLocalLoggerInline(metadata: [
        "iteration-\(iterations)-key": "iteration-\(iterations)-value"
    ]) { logger in
        logger.info("I am a recursive function using task local logger")
        implicitLogger(iterations: iterations - 1)
        logger.info("I am done")
    }
}

/// MARK: - benchmarking functions

func benchmarkExplicitLoggerPropagation(_ iterations: Int, _ metrics: [BenchmarkMetric]) {
    var logger = Logger(label: "TaskLocalPlaygroundLogger_explicit")
    // logger.handler = NoOpLogHandler(label: "NoOpLogHandler_explicit")
    Benchmark(
        "TaskLocalPlaygroundBenchmark",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        explicitLogger(logger: logger)
    }
}

func benchmarkImplicitTaskLocalLoggerPropagation(_ iterations: Int, _ metrics: [BenchmarkMetric]) {
    Benchmark(
        "TaskLocalPlaygroundBenchmark",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        implicitLogger()
    }
}

// let taskLocalBenchmarks: @Sendable () -> Void = {
//     let iterations = 1_000_000
//     let metrics: [BenchmarkMetric] = [.instructions, .objectAllocCount, .wallClock]

//     benchmarkExplicitLoggerPropagation(iterations, metrics)
//     // benchmarkImplicitTaskLocalLoggerPropagation(iterations, metrics)
// }
