import SwiftUI
import UIKit
import XCTest
@testable import ReplayXI

@MainActor
final class DashboardRosterFollowTests: XCTestCase {
    func testNativeRosterWhenEnteringOpponentPOVAndCrossingTeams() throws {
        let store = ReplayStore()
        store.prepareForLocalExperience()
        store.selectScenario(id: "eleven-eyes")
        XCTAssertEqual(store.selectedScenarioID, "eleven-eyes")
        store.seek(to: 5)
        let away = try XCTUnwrap(store.selectedScenario.awayPlayers.last)
        store.openLocalPlayerPOV(away.id)
        let view = PlaybackConsole().environment(store)
            .environment(\.colorScheme, .dark).padding(16).background(ReplayTheme.navy)
        let host = UIHostingController(rootView: view)
        let size = CGSize(width: 760, height: 420)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        try capture(host, name: "dashboard-roster-initial-opponent", expectedAtEnd: true)

        let home = try XCTUnwrap(store.selectedScenario.homePlayers.last)
        store.openLocalPlayerPOV(home.id)
        try capture(host, name: "dashboard-roster-last-home", expectedAtEnd: true)
        let next = try XCTUnwrap(PlaybackPerspectiveNavigation.adjacentPlayerID(
            in: store.selectedScenario.players, activeID: home.id,
            localFallbackID: home.id, offset: 1))
        XCTAssertEqual(store.selectedScenario.player(id: next)?.team, .away)
        store.openLocalPlayerPOV(next)
        try capture(host, name: "dashboard-roster-next-opponent", expectedAtEnd: false)
        XCTAssertEqual(store.playhead, 5)
        XCTAssertEqual(store.activePerspectiveID, next)
        XCTAssertEqual(store.viewMode, .firstPerson)
    }

    func testNativeReferenceRosterRetainsFocusWhenBlockedAndRefreshesAfterScenarioChange() throws {
        let store = ReplayStore(scenarios: DemoScenarios.catalogue)
        store.prepareForLocalExperience()
        store.selectScenario(id: "final-36-counter-v2")
        XCTAssertEqual(store.selectedScenarioID, "final-36-counter-v2")
        store.seek(to: 5)
        let away = try XCTUnwrap(store.selectedScenario.awayPlayers.last)
        store.openLocalPlayerPOV(away.id)
        let view = PlaybackConsole().environment(store)
            .environment(\.colorScheme, .dark).padding(16).background(ReplayTheme.navy)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 760, height: 420))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        try capture(host, name: "dashboard-reference-opponent", expectedAtEnd: true)

        XCTAssertTrue(store.beginTimelineScrub())
        store.openLocalPlayerPOV(try XCTUnwrap(store.selectedScenario.homePlayers.first).id)
        XCTAssertEqual(store.activePerspectiveID, away.id)
        try capture(host, name: "dashboard-reference-blocked", expectedAtEnd: true)
        store.cancelTimelineScrub()
        store.selectScenario(id: "city-45-overlap-header")
        XCTAssertEqual(store.selectedScenarioID, "city-45-overlap-header")
        let home = try XCTUnwrap(store.selectedScenario.homePlayers.last)
        store.openLocalPlayerPOV(home.id)
        try capture(host, name: "dashboard-reference-changed", expectedAtEnd: true)
        XCTAssertEqual(store.playhead, 0)
        XCTAssertEqual(store.activePerspectiveID, home.id)
    }

    func testConsoleRevealsOnlyPresentationStateAndKeepsIconViewControlsNamed() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(
            "ReplayXI/UI/ReplayDashboardView.swift"), encoding: .utf8)
        let lower = try XCTUnwrap(source.range(of: "struct PlaybackConsole: View")?.lowerBound)
        let upper = try XCTUnwrap(source.range(of: "struct DashboardPlayerRailContent")?.lowerBound)
        let console = String(source[lower..<upper])
        XCTAssertTrue(console.contains(".scrollPosition(id: $rosterScrollID, anchor: .center)"))
        XCTAssertTrue(console.contains(".scrollTargetLayout()"))
        XCTAssertTrue(console.contains(".onAppear { revealCurrentRosterPlayer() }"))
        XCTAssertTrue(console.contains(".onChange(of: store.activePerspectiveID)"))
        XCTAssertTrue(console.contains(".onChange(of: store.selectedScenarioID)"))
        XCTAssertTrue(console.contains(".labelStyle(.iconOnly)"))
        XCTAssertTrue(console.contains(".frame(minWidth: 44, minHeight: 44)"))
        XCTAssertTrue(console.contains(".help(mode.title)"))
        XCTAssertTrue(console.contains(".accessibilityLabel(mode.title)"))
        let start = try XCTUnwrap(console.range(of: "private func revealCurrentRosterPlayer()")?.lowerBound)
        let end = try XCTUnwrap(console.range(of: "private func openAdjacentPlayerPOV")?.lowerBound)
        let reveal = console[start..<end]
        XCTAssertTrue(reveal.contains("rosterTeam = player.team"))
        XCTAssertTrue(reveal.contains("rosterScrollID = player.id"))
        XCTAssertFalse(reveal.contains("store.openLocalPlayerPOV"))
        XCTAssertFalse(reveal.contains("store.seek"))
    }

    func testNativeRosterAtLargestAccessibilityText() throws {
        let store = ReplayStore(scenarios: DemoScenarios.catalogue)
        store.prepareForLocalExperience()
        store.selectScenario(id: "final-36-counter-v2")
        XCTAssertEqual(store.selectedScenarioID, "final-36-counter-v2")
        let away = try XCTUnwrap(store.selectedScenario.awayPlayers.last)
        store.openLocalPlayerPOV(away.id)
        let view = PlaybackConsole().environment(store)
            .environment(\.colorScheme, .dark).dynamicTypeSize(.accessibility5)
            .padding(16).background(ReplayTheme.navy)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 760, height: 1100))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = window.bounds
        try capture(host, name: "dashboard-reference-accessibility5", expectedAtEnd: true)
        XCTAssertEqual(store.activePerspectiveID, away.id)
    }

    private func capture<Content: View>(_ host: UIHostingController<Content>, name: String,
                                       expectedAtEnd: Bool) throws {
        host.view.setNeedsLayout()
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
        func scrolls(in view: UIView) -> [UIScrollView] {
            let current = (view as? UIScrollView).map { [$0] } ?? []
            return current + view.subviews.flatMap { scrolls(in: $0) }
        }
        let nativeScrolls = scrolls(in: host.view)
        XCTAssertEqual(nativeScrolls.count, 2, "Native cue and player scroll views")
        let roster = try XCTUnwrap(nativeScrolls.last)
        let maximumOffset = max(roster.contentSize.width - roster.bounds.width, 0)
        XCTAssertGreaterThan(maximumOffset, 100, "Fixture must require real scrolling to its last player")
        XCTAssertEqual(roster.contentOffset.x, expectedAtEnd ? maximumOffset : 0, accuracy: 1,
                       "The selected player must be visible without a manual swipe")
        let rows = nativeScrolls.map { scroll in
            ["width": scroll.bounds.width, "height": scroll.bounds.height,
             "contentWidth": scroll.contentSize.width, "contentHeight": scroll.contentSize.height,
             "offsetX": scroll.contentOffset.x, "offsetY": scroll.contentOffset.y]
        }
        let report = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: .sortedKeys),
                                   uniformTypeIdentifier: "public.json")
        report.name = name + "-native-scrolls"
        report.lifetime = .keepAlways
        add(report)
    }
}
