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

import Logging

if #available(macOS 11, *) {
    let myOSLogHandler = OSLogHandler(subsystem: "com.kukushechkin.OSLogHandlerDemo", category: "Test")
    
    var logger = Logger(label: "OSLogHandlerDemo.main")
    logger.handler = myOSLogHandler
    
    logger.debug("this is a debug message", metadata: [
        "foo": Logger.MetadataValue.string("42")
    ])
}
