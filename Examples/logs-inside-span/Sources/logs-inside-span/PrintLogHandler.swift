import Logging

package struct PrintLogHandler: LogHandler {
    package var metadata: Logger.Metadata = [:]
    package var logLevel: Logger.Level = .info
    let label: String

    init(label: String) {
        self.label = label
    }

    package subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { self.metadata[key] }
        set { self.metadata[key] = newValue }
    }

    package func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        print(message)
    }
}
