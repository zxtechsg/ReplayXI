import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class DashboardTransportLayoutTests: XCTestCase {
    func testNativeTransportRegularText() throws {
        try capture(size: .large, name: "dashboard-transport-regular")
    }

    func testNativeTransportLargestAccessibilityText() throws {
        try capture(size: .accessibility5, name: "dashboard-transport-accessibility5")
    }

    func testPairingIconExistsAndSkipButtonsShowSeconds() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let pairing = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/LocalNetwork/ReplayXIMacPairingBar.swift"), encoding: .utf8)
        let images = try NSRegularExpression(pattern: #"Image\(systemName: "([^"]+)"\)"#)
        let names = images.matches(in: pairing, range: NSRange(pairing.startIndex..., in: pairing))
        XCTAssertFalse(names.isEmpty)
        for match in names {
            let range = try XCTUnwrap(Range(match.range(at: 1), in: pairing))
            let name = String(pairing[range])
            XCTAssertNotNil(UIImage(systemName: name), "Missing pairing icon: \(name)")
        }
        let dashboard = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/UI/ReplayDashboardView.swift"), encoding: .utf8)
        XCTAssertTrue(dashboard.contains("Text(\"−1s\")"))
        XCTAssertTrue(dashboard.contains("Text(\"+1s\")"))
        XCTAssertFalse(dashboard.contains("gobackward.1"))
        XCTAssertFalse(dashboard.contains("goforward.1"))
    }

    func testTransportUsesMatchTeamAndShortPositionWithFullAccessibleIdentity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("ReplayXI/UI/ReplayDashboardView.swift"), encoding: .utf8)
        let lower = try XCTUnwrap(source.range(of: "struct DashboardTransport: View")?.lowerBound)
        let upper = try XCTUnwrap(source.range(of: "struct PlaybackConsole: View")?.lowerBound)
        let transport = source[lower..<upper]
        XCTAssertTrue(transport.contains("FootballReferenceScenarios.teamTitle(player.team, in: scenario)"))
        XCTAssertTrue(transport.contains("player.positionCode"))
        XCTAssertTrue(transport.contains("player.displayName"))
        XCTAssertTrue(transport.contains("player.role"))
        XCTAssertFalse(transport.contains("player.team.compactTitle"))
    }

    private func capture(size: DynamicTypeSize, name: String) throws {
        let store = ReplayStore(scenarios: DemoScenarios.catalogue)
        store.prepareForLocalExperience()
        store.selectScenario(id: "final-36-counter-v2")
        XCTAssertEqual(store.selectedScenarioID, "final-36-counter-v2")
        store.seek(to: 5)
        let player = try XCTUnwrap(store.selectedScenario.awayPlayers.last)
        store.openLocalPlayerPOV(player.id)
        let view = DashboardTransport().environment(store)
            .environment(\.colorScheme, .dark).dynamicTypeSize(size)
            .padding(16).background(ReplayTheme.navy)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 760, height: 620))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(data: try XCTUnwrap(image.pngData()), uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(store.playhead, 5)
        XCTAssertEqual(store.activePerspectiveID, player.id)
        XCTAssertFalse(store.hasActiveTimelineScrub)
    }
}
