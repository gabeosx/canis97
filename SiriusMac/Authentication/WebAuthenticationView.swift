import SwiftUI
import WebKit

struct WebAuthenticationView: NSViewRepresentable {
    let bridge: WebAuthenticationBridge

    func makeNSView(context: Context) -> WKWebView {
        bridge.makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
