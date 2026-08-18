import SwiftUI
import WebKit

@MainActor
final class WebAuthenticationWebViewHost: NSView {
    func install(_ webView: WKWebView) {
        guard subviews.first !== webView else { return }

        subviews.forEach { $0.removeFromSuperview() }
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

struct WebAuthenticationView: NSViewRepresentable {
    let bridge: WebAuthenticationBridge

    func makeNSView(context: Context) -> WebAuthenticationWebViewHost {
        let host = WebAuthenticationWebViewHost(frame: .zero)
        host.install(bridge.makeWebView())
        return host
    }

    func updateNSView(_ nsView: WebAuthenticationWebViewHost, context: Context) {
        nsView.install(bridge.makeWebView())
    }
}
