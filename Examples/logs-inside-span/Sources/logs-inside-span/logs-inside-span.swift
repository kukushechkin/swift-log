import Instrumentation
import Logging
import Metrics
import OTel
import ServiceLifecycle
import UnixSignals
import Tracing

final class FooService: Service {
    let logger: Logger
    
    init(logger: Logger) {
        self.logger = logger
    }
    
    func run() async throws {
        // Here we use the explicitly provided non-multiplexed logger
        self.logger.info("Hello, world!")
        
        // Here we use the bootstrapped multiplexed logger
        let localLogger = Logger(label: "FooService")
        localLogger.info("Hello, local world!")

        withSpan("FooService.run") { _ in
            // Here we use the explicitly provided non-multiplexed logger
            self.logger.info("SPAN: Hello, world!")
            
            // Here we use the bootstrapped multiplexed logger
            let localLogger = Logger(label: "FooService")
            localLogger.info("SPAN: Hello, local world!")
        }
        
        // Keep running
        while true {
            try await Task.sleep(for: .seconds(1))
        }
    }
}

func makeTelemetryService(
    serviceName: String
) throws -> (logger: Logger, service: ServiceGroup) {
    var otelConfig = OTel.Configuration.default
    otelConfig.logs.enabled = true
    otelConfig.metrics.enabled = false
    otelConfig.traces.enabled = true
    otelConfig.serviceName = serviceName
        
    // Bootstrap tracing
    let otelTracingBackend = try OTel.makeTracingBackend(configuration: otelConfig)
    InstrumentationSystem.bootstrap(otelTracingBackend.factory)

    // Make one non-multiplexed logger, return it
    var logger = Logger(label: serviceName)
    logger.logLevel = .trace
    
    // Bootstrap logging
    let otelLoggingBackend = try OTel.makeLoggingBackend(configuration: otelConfig)
    LoggingSystem.bootstrap { label in
        var handler = MultiplexLogHandler([
            PrintLogHandler(label: label),
            otelLoggingBackend.factory(label),
        ])
        handler.logLevel = .debug
        return handler
    }
    
    // Create a named service group
    let serviceGroup = ServiceGroup(
        services: [
            otelTracingBackend.service,
        ],
        logger: logger,
    )
    let namedServiceConfiguration = ServiceGroupConfiguration.ServiceConfiguration(
        service: serviceGroup,
        serviceName: "Telemetry"
    )
    let serviceGroupConfiguration = ServiceGroupConfiguration(
        services: [namedServiceConfiguration],
        logger: logger
    )
        
    return (
        logger,
        ServiceGroup(configuration: serviceGroupConfiguration),
    )
}

@main
struct Application {
    public static func main() async throws {
        let applicationName = "CLIExample"

        // Initialize all telemetry services
        let (logger, telemetryService) = try makeTelemetryService(
            serviceName: applicationName
        )
        
        // Create a service simulating some important work
        let fooService = FooService(
            logger: logger
        )

        // Create a nested service group, which will handle the ordered shutdown.
        var serviceConfigs: [ServiceGroupConfiguration.ServiceConfiguration] = []
        for service in [telemetryService, fooService] as [Service] {
            serviceConfigs.append(.init(
                service: service,
                successTerminationBehavior: .gracefullyShutdownGroup,
                failureTerminationBehavior: .gracefullyShutdownGroup
            ))
        }
        let serviceGroup = ServiceGroup(
            configuration: .init(
                services: serviceConfigs,
                gracefulShutdownSignals: [.sigint],
                cancellationSignals: [.sigterm],
                logger: logger,
            )
        )
        
        try await serviceGroup.run()
    }
}
