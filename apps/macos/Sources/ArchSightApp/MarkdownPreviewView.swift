import ArchSightKit
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let content: String
    var preferences: ReadingPreferences = .default

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Named themes paint their own background via CSS; the system theme stays
        // transparent so it sits flush on the SwiftUI background.
        let theme = ReadingTheme.theme(for: preferences.theme)
        let drawsBackground = !theme.isDynamic
        if context.coordinator.lastDrawsBackground != drawsBackground {
            webView.setValue(drawsBackground, forKey: "drawsBackground")
            context.coordinator.lastDrawsBackground = drawsBackground
        }

        let html = MarkdownPreviewHTML.render(content, preferences: preferences)
        guard context.coordinator.lastHTML != html else {
            return
        }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: URL(string: "https://archsight.local/"))
    }

    final class Coordinator {
        var lastHTML: String?
        var lastDrawsBackground: Bool?
    }
}
