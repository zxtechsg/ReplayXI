import SwiftUI
import WebKit

/// Official embedded player only. No video extraction, proxying or downloads.
struct ReplayYouTubePlayer: UIViewRepresentable {
    let reference: ReplayVideoReference
    let onReady: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onReady: onReady, onFailure: onFailure) }

    func makeUIView(context: Context) -> WKWebView {
        Self.makeWebView(reference: reference, coordinator: context.coordinator)
    }

    /// Shared by the opt-in UI and a separately opted-in integration check.
    /// Keeping one constructor prevents test-only referrers or playback settings.
    @MainActor
    static func makeWebView(reference: ReplayVideoReference, coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(coordinator, name: "replayVideo")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = coordinator
        guard ReplayReferenceEmbed.accepts(videoID: reference.videoID),
              let origin = ReplayReferenceEmbed.clientOrigin(
                bundleID: Bundle.main.bundleIdentifier ?? "ReplayXI.local") else {
            Task { @MainActor in coordinator.onFailure("This video reference is invalid.") }
            return webView
        }
        // A genuine client baseURL supplies Referer; never impersonate another
        // website to evade the publisher's embedding restrictions.
        webView.loadHTMLString(Self.document(reference: reference, origin: origin), baseURL: origin)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        stop(uiView)
    }

    @MainActor
    static func stop(_ uiView: WKWebView) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "replayVideo")
        uiView.navigationDelegate = nil
        uiView.loadHTMLString("", baseURL: nil)
    }

    private static func document(reference: ReplayVideoReference, origin: URL) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body,#player{margin:0;width:100%;height:100%;background:#000;overflow:hidden}</style>
        </head><body><div id="player"></div><script>
        function report(value){window.webkit.messageHandlers.replayVideo.postMessage(value);}
        function onYouTubeIframeAPIReady(){new YT.Player('player',{
          width:'100%',height:'100%',videoId:'\(reference.videoID)',
          playerVars:{playsinline:1,controls:1,autoplay:0,start:\(reference.startSeconds),
            end:\(reference.endSeconds),origin:'\(origin.absoluteString)'},
          events:{onReady:function(){report({ready:true});},
            onError:function(e){report({error:e.data});}}
        });}
        </script><script src="https://www.youtube.com/iframe_api"></script></body></html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onReady: () -> Void
        let onFailure: (String) -> Void

        init(onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
            self.onReady = onReady
            self.onFailure = onFailure
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "replayVideo", let body = message.body as? [String: Any] else { return }
            if body["ready"] as? Bool == true { onReady() }
            if let code = body["error"] as? Int {
                onFailure(ReplayReferenceEmbed.errorMessage(code: code))
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) { handle(error) }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) { handle(error) }

        private func handle(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            onFailure("Video unavailable. Check your connection or open the source.")
        }
    }
}
