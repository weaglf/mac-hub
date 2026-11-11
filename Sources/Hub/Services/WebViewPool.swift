import WebKit

/// Her web servisi için tek bir WKWebView tutar; ana ekrana dönüp geri gelince kaldığın yerden devam eder.
/// Oturumlar (Netflix, YouTube girişleri vb.) Hub'ın kendi çerez deposunda kalıcıdır.
@MainActor
final class WebViewPool: NSObject, WKUIDelegate {
    static let shared = WebViewPool()
    private var views: [String: WKWebView] = [:]

    func webView(for session: WebSession) -> WKWebView {
        if let existing = views[session.tileID] {
            if let url = session.url { existing.load(URLRequest(url: url)) }
            else if existing.url == nil { existing.load(URLRequest(url: session.homeURL)) }
            return existing
        }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        // Bazı servisler (Netflix, Google girişi) yalnızca Safari kimliğini kabul eder.
        config.applicationNameForUserAgent = "Version/26.2 Safari/605.1.15"

        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        view.uiDelegate = self
        view.load(URLRequest(url: session.url ?? session.homeURL))
        views[session.tileID] = view
        return view
    }

    func existing(_ tileID: String) -> WKWebView? { views[tileID] }

    /// Açık her web servisinin WebKit süreci (bellek widget'ı için). WebKit'in kendi alanı;
    /// bulunamazsa o servis "ortak WebKit" payına düşer.
    func processIDs() -> [String: pid_t] {
        let key = "_webProcessIdentifier"
        var result: [String: pid_t] = [:]
        for (tileID, view) in views where view.responds(to: NSSelectorFromString(key)) {
            if let pid = (view.value(forKey: key) as? NSNumber)?.int32Value, pid > 0 { result[tileID] = pid }
        }
        return result
    }

    func pause(_ tileID: String) {
        views[tileID]?.pauseAllMediaPlayback(completionHandler: nil)
    }

    /// Görünümü tamamen bırakır; WebKit sayfayı ve sesini kapatır. Oturum çerezleri kalır.
    func close(_ tileID: String) {
        guard let view = views.removeValue(forKey: tileID) else { return }
        view.pauseAllMediaPlayback(completionHandler: nil)
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        view.removeFromSuperview()
    }

    // target="_blank" bağlantıları aynı görünümde aç.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}
