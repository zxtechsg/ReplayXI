import Foundation
import Observation

/// Debug display routes need an explicit opt-in. Old XCTest/Simulator flags
/// must not reopen a room or discard the user's saved review on normal launch.
struct ReplayLaunchConfiguration: Sendable {
    let automationArguments: [String]
    let usesTransientReviews: Bool

    init(arguments: [String], environment: [String: String],
         hasXCTestRuntime: Bool, isDebugBuild: Bool) {
        let isTestHost = hasXCTestRuntime || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
        let permitsAutomation = isDebugBuild && !isTestHost && arguments.contains("--replayxi-demo")
        automationArguments = permitsAutomation ? arguments.filter { $0.hasPrefix("--replayxi-") } : []
        usesTransientReviews = isTestHost || permitsAutomation
    }

    static var current: Self {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return Self(arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment,
            hasXCTestRuntime: NSClassFromString("XCTestCase") != nil, isDebugBuild: isDebugBuild)
    }
}

/// App-owned rather than view-owned: reopening the dashboard cannot replay an
/// old automatic entry, draft, seek or saved-review-sheet request.
@MainActor
@Observable
final class ReplayLaunchSession {
    let configuration: ReplayLaunchConfiguration
    @ObservationIgnored private var consumedRoutes = Set<String>()

    init(configuration: ReplayLaunchConfiguration) { self.configuration = configuration }

    func consumeArguments(for route: String) -> [String]? {
        guard !configuration.automationArguments.isEmpty,
              consumedRoutes.insert(route).inserted else { return nil }
        return configuration.automationArguments
    }
}
