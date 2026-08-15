import SwiftUI
import WebKit
import AppKit

/// 承载 DeepSeek Web UI 的 WKWebView 包装。
/// 服务器尚未就绪时加载会失败，这里会自动重试（本地服务通常 1~2 秒内就绪）。
struct WebView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            nsView.reload()
        }
        if nsView.url == nil {
            nsView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let url: URL
        private var retryTask: Task<Void, Never>?
        var lastReloadToken = 0

        init(url: URL) {
            self.url = url
        }

        // target=_blank / window.open 的链接交给系统默认浏览器，不在 App 内开新窗口
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let target = navigationAction.request.url {
                NSWorkspace.shared.open(target)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(webView, error: error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleLoadFailure(webView, error: error)
        }

        /// 加载失败（服务器未就绪/连接中断）→ 1.5 秒后自动重试
        private func handleLoadFailure(_ webView: WKWebView, error: Error) {
            let nsError = error as NSError
            // 用户主动取消导航不算失败
            if nsError.code == NSURLErrorCancelled { return }
            NSLog("DeepSeek WebView 加载失败，1.5s 后重试: %@", nsError.localizedDescription)
            retryTask?.cancel()
            retryTask = Task { [weak self, weak webView] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled, let self, let webView else { return }
                if webView.url == nil || (webView.url?.host == self.url.host) {
                    webView.load(URLRequest(url: self.url))
                }
            }
        }
    }
}
