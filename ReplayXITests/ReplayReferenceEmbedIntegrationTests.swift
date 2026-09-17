import WebKit
import XCTest
@testable import ReplayXI

/// Network access is deliberately excluded from the default regression suite.
/// A ready callback proves initialization only, never successful video playback.
@MainActor
final class ReplayReferenceEmbedIntegrationTests: XCTestCase {
    func testOptInOfficialPlayerReportsRealInitializationOrFailure() async throws {
        guard ProcessInfo.processInfo.environment["REPLAYXI_TEST_YOUTUBE"] == "1" else {
            throw XCTSkip("Set REPLAYXI_TEST_YOUTUBE=1 for the bounded official embed check.")
        }
        let reference = try XCTUnwrap(ReplayReferenceLibrary.reference(for: "final-81-volley"))
        let firstEvent = expectation(description: "Official player initialization or explicit failure")
        var hasFirstEvent = false
        var initialized = false
        var errors: [String] = []
        var events: [String] = [
            "Source: \(reference.sourceURL.absoluteString)",
            "Client: \(Bundle.main.bundleIdentifier ?? "unknown")",
            "Uses production player HTML/configuration. No play command is sent."
        ]
        let started = Date()
        let coordinator = ReplayYouTubePlayer.Coordinator(onReady: {
            initialized = true
            events.append("\(Date().timeIntervalSince(started))s: onReady (initialization only)")
            if !hasFirstEvent { hasFirstEvent = true; firstEvent.fulfill() }
        }, onFailure: { message in
            errors.append(message)
            events.append("\(Date().timeIntervalSince(started))s: failure: \(message)")
            if !hasFirstEvent { hasFirstEvent = true; firstEvent.fulfill() }
        })
        let webView = ReplayYouTubePlayer.makeWebView(reference: reference, coordinator: coordinator)
        webView.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        defer { ReplayYouTubePlayer.stop(webView) }
        await fulfillment(of: [firstEvent], timeout: 20)
        // Some restrictions arrive after the first ready callback. Observe a
        // bounded interval, without attempting autoplay or a synthetic click.
        try await Task.sleep(for: .seconds(3))
        events.append("Playback was NOT requested or verified. Publisher restrictions may appear after Play.")
        if !hasFirstEvent { events.append("No callback within 20 seconds.") }
        let attachment = XCTAttachment(string: events.joined(separator: "\n"))
        attachment.name = "Official YouTube embed – actual network outcome"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(initialized, "The official player did not initialize; see the actual outcome attachment.")
        XCTAssertTrue(errors.isEmpty, "The official player reported: \(errors.joined(separator: "; "))")
    }
}
