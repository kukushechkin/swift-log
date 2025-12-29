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

    #if BenchmarkTaskLocalWithConsoleLogger
    @TaskLocal
    static var taskLocalLogger = Logger(label: "TaskLocalPlaygroundLogger_global")
    #else
    @TaskLocal
    static var taskLocalLogger = Logger(label: "TaskLocalPlaygroundLogger_global") { _ in
        NoOpLogHandler(label: "NoOpLogHandler_global")
    }
    #endif

    @inline(__always)
    static func withTaskLocalLoggerInline(metadata: Logger.Metadata, _ body: (Logger) -> Void) {
        let newLogger = self.taskLocalLogger.with(additionalMetadata: metadata)
        self.$taskLocalLogger.withValue(newLogger) {
            body(self.taskLocalLogger)
        }
    }
}

/// MARK: - payload functions

@inline(never)
func explicitLogger(logger: Logger, iterations: Int = 100, moreMetadata: Bool = true) {
    if iterations == 0 {
        return
    }
    logger.info("I am a recursive function")
    let additionalMetadata: Logger.Metadata = if moreMetadata {[
        "iteration-\(iterations)-key1": "iteration-\(iterations)-value1",
        "iteration-\(iterations)-key2": "iteration-\(iterations)-value2",
        "iteration-\(iterations)-key3": "iteration-\(iterations)-value3"
    ]} else {[
        "iteration-\(iterations)-key1": "iteration-\(iterations)-value1"
    ]}
    explicitLogger(
        logger: logger.with(additionalMetadata: additionalMetadata),
        iterations: iterations - 1
    )
    logger.info("I am done")
}

@inline(never)
func implicitLogger(iterations: Int = 100, moreMetadata: Bool = true) {
    if iterations == 0 {
        return
    }
    let additionalMetadata: Logger.Metadata = if moreMetadata {[
        "iteration-\(iterations)-key1": "iteration-\(iterations)-value1",
        "iteration-\(iterations)-key2": "iteration-\(iterations)-value2",
        "iteration-\(iterations)-key3": "iteration-\(iterations)-value3"
    ]} else {[
        "iteration-\(iterations)-key1": "iteration-\(iterations)-value1"
    ]}
    GlobalLoggerContext.withTaskLocalLoggerInline(metadata: additionalMetadata) { logger in
        logger.info("I am a recursive function using task local logger")
        implicitLogger(iterations: iterations - 1)
        logger.info("I am done")
    }
}

/// MARK: - benchmarking functions

func benchmarkLoggerPropagation() {
    let iterations = 1_000_000_000
    let taskLocalBenchmarksMetrics: [BenchmarkMetric] = [.instructions, .objectAllocCount, .wallClock]

    #if BenchmarkTaskLocalLogger
    benchmarkImplicitTaskLocalLoggerPropagation(iterations, taskLocalBenchmarksMetrics)
    #endif

    #if BenchmarkExplicitLogger
    benchmarkExplicitLoggerPropagation(iterations, taskLocalBenchmarksMetrics)
    #endif
}

func benchmarkExplicitLoggerPropagation(_ iterations: Int, _ metrics: [BenchmarkMetric]) {
    var logger = Logger(label: "TaskLocalPlaygroundLogger_explicit")
    #if !BenchmarkTaskLocalWithConsoleLogger
    logger.handler = NoOpLogHandler(label: "NoOpLogHandler_explicit")
    #endif
    Benchmark(
        "TaskLocalPlaygroundBenchmark",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        explicitLogger(logger: logger)
    }
    Benchmark(
        "TaskLocalPlaygroundBenchmark_singleMetadataValue",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        explicitLogger(logger: logger, moreMetadata: false)
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
    Benchmark(
        "TaskLocalPlaygroundBenchmark_singleMetadataValue",
        configuration: .init(
            metrics: metrics,
            maxIterations: iterations
        )
    ) { benchmark in
        implicitLogger(moreMetadata: false)
    }
}
