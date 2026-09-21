import Foundation
import WebKit

/// One ephemeral store is shared by the main page and every SSO popup.
@MainActor
final class SchoolPortalSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let configuration: SchoolPortalConfiguration
    private(set) var state: SchoolPortalSessionState = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var lastParseResult: SchoolScheduleParseResult?
    var onStateChange: ((SchoolPortalSessionState) -> Void)?
    var onTableMessage: ((SchoolPortalFrameMessage) -> Void)?
    var onParseResult: ((SchoolScheduleParseResult) -> Void)?
    /// UI must display this view (or webView when nil), and wire its close button
    /// to closePopup(). The returned popup is the same one held by window.open.
    var onPopupChange: ((WKWebView?) -> Void)?
    var activeWebView: WKWebView { childWebViews.last ?? webView }

    private let bridge: SchoolPortalMessageBridge
    private var childWebViews: [WKWebView] = []
    private var extractionID: String?
    private var tables: [SchoolPortalFrameMessage] = []
    private var observedFrames = Set<String>()
    private var finishWork: DispatchWorkItem?
    private var deadlineWork: DispatchWorkItem?
    private var bootstrapping = false

    init(configuration: SchoolPortalConfiguration) {
        self.configuration = configuration
        bridge = SchoolPortalMessageBridge()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.processPool = WKProcessPool()
        if #available(iOS 14.0, *) { config.defaultWebpagePreferences.allowsContentJavaScript = true }
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.loginSupportScript(handler: configuration.extractionMessageName), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: Self.extractionScript(handler: configuration.extractionMessageName, allowedHosts: configuration.allowedHosts), injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        controller.add(bridge, name: configuration.extractionMessageName)
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        bridge.session = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    /// Password submission and second-factor challenges stay inside the portal.
    /// This signature accepts the existing caller contract but stores no secrets.
    func start(credentials: SchoolPortalCredentials? = nil) {
        stop()
        guard isAllowed(configuration.loginURL) else { fail("登录地址不在学校 HTTPS 域名白名单内。"); return }
        let entry = configuration.sessionBootstrapURL ?? configuration.loginURL
        guard isAllowed(entry) else { fail("登录初始化地址不在学校 HTTPS 域名白名单内。"); return }
        bootstrapping = configuration.sessionBootstrapURL != nil
        publish(.loading)
        webView.load(URLRequest(url: entry, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func stop() {
        cancelExtraction()
        bootstrapping = false
        webView.stopLoading()
        childWebViews.forEach { $0.stopLoading(); $0.navigationDelegate = nil; $0.uiDelegate = nil }
        childWebViews.removeAll()
        onPopupChange?(nil)
        lastParseResult = nil
        state = .idle
    }

    func closePopup() {
        guard let popup = childWebViews.popLast() else { return }
        popup.stopLoading()
        popup.navigationDelegate = nil
        popup.uiDelegate = nil
        cancelExtraction()
        onPopupChange?(childWebViews.last)
        publish(.ready)
    }

    func requestExtraction() {
        cancelExtraction()
        lastParseResult = nil
        let requestID = UUID().uuidString
        extractionID = requestID
        publish(.extracting)
        // Each allowed frame forwards the request to its direct children. This
        // reaches grandchildren behind cross-origin boundaries without DOM access.
        let script = "window.postMessage({sanqianSchedule:'extract',requestID:\(Self.js(requestID))},location.origin);"
        let deadline = DispatchWorkItem { [weak self] in self?.finishExtraction(requestID, timedOut: true) }
        deadlineWork = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: deadline)
        activeWebView.evaluateJavaScript(script) { [weak self] _, error in
            guard let self, self.extractionID == requestID else { return }
            if error != nil { self.cancelExtraction(); self.fail("无法读取当前网页，请等待页面加载后重试。"); return }
        }
    }

    func clearEphemeralData(completion: (() -> Void)? = nil) {
        stop()
        let store = webView.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            DispatchQueue.main.async { completion?() }
        }
    }

    private func cancelExtraction() {
        finishWork?.cancel(); deadlineWork?.cancel()
        finishWork = nil; deadlineWork = nil
        extractionID = nil
        tables.removeAll(); observedFrames.removeAll()
    }

    private func publish(_ phase: SchoolPortalPhase, error: String? = nil) {
        // A loaded page or a parsed table is not proof of an authenticated session.
        state = SchoolPortalSessionState(phase: phase, currentURL: SchoolPortalSecurity.sanitizedURL(activeWebView.url), isLoggedIn: false, extractionID: extractionID, errorMessage: error)
    }

    private func fail(_ message: String) { publish(.failed, error: message) }

    private func isAllowed(_ url: URL?) -> Bool {
        guard let url, url.user == nil, url.password == nil else { return false }
        return SchoolPortalSecurity.allows(scheme: url.scheme ?? "", host: url.host ?? "", allowedHosts: configuration.allowedHosts)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        if message.name == configuration.extractionMessageName,
           message.frameInfo.isMainFrame, origin.protocol == "https", origin.host == "iam.zgysyjy.org.cn",
           origin.port == 443 || origin.port == 0,
           message.frameInfo.request.url?.path == "/am/mLogin/login.html",
           let payload = message.body as? [String: Any], payload["kind"] as? String == "loginStatus",
           let code = payload["code"] as? String {
            let messages = [
                "captchaChanged": "验证码已刷新，请输入当前图片中的验证码。",
                "requestFailed": "学校登录请求失败，请刷新页面后重试。",
                "scriptFailed": "学校登录页面执行失败，请刷新页面后重试。"
            ]
            if let text = messages[code] { publish(.needsManualAuthentication, error: text) }
            return
        }
        guard message.name == configuration.extractionMessageName,
              SchoolPortalSecurity.allows(scheme: origin.protocol, host: origin.host, allowedHosts: configuration.allowedHosts),
              let payload = SchoolPortalFrameMessage(body: message.body),
              let requestID = extractionID, payload.requestID == requestID,
              payload.rows.count <= 128, payload.rows.allSatisfy({ $0.count <= 32 && $0.allSatisfy({ $0.text.count <= 2000 && (1...128).contains($0.rowSpan) && (1...32).contains($0.colSpan) }) }) else { return }
        let url = SchoolPortalSecurity.sanitizedURL(message.frameInfo.request.url) ?? "https://\(origin.host)/"
        let trusted = SchoolPortalFrameMessage(version: 1, kind: "scheduleTables", requestID: requestID,
            frame: SchoolPortalFrameIdentity(url: url, securityOrigin: "https://\(origin.host):\(origin.port)", isMainFrame: message.frameInfo.isMainFrame),
            title: "", innerText: payload.rows.flatMap { $0 }.map(\.text).joined(separator: "\n"), html: "", rows: payload.rows, truncated: payload.truncated)
        observedFrames.insert(url)
        if !trusted.rows.isEmpty && !tables.contains(trusted) {
            tables.append(trusted)
            onTableMessage?(trusted)
        }
        finishWork?.cancel()
        let finish = DispatchWorkItem { [weak self] in self?.finishExtraction(requestID, timedOut: false) }
        finishWork = finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: finish)
    }

    private func finishExtraction(_ requestID: String, timedOut: Bool) {
        guard extractionID == requestID else { return }
        let parsed = SchoolScheduleParser.parse(tables: tables, frameCount: observedFrames.count, sourceURL: SchoolPortalSecurity.sanitizedURL(activeWebView.url))
        let result = SchoolScheduleParseResult(source: parsed.source, sourceURL: parsed.sourceURL, frameCount: parsed.frameCount, tableCount: parsed.tableCount, drafts: parsed.drafts, warnings: parsed.warnings + [timedOut ? "读取窗口已结束；未响应或仍在加载的页面需重新读取。" : "已汇总本次响应的表格；仍在加载的页面需重新读取。"], timetableText: parsed.timetableText)
        cancelExtraction()
        guard result.canReview else { fail(parsed.warnings.last ?? "当前页面没有可识别课表，请进入「我的课表」后重新读取。"); return }
        lastParseResult = result
        publish(.parsed)
        onParseResult?(result)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let blankPopup = childWebViews.contains(where: { $0 === webView }) && navigationAction.request.url?.absoluteString == "about:blank"
        if let url = navigationAction.request.url,
           url.scheme?.lowercased() == "http",
           url.host?.lowercased() == "iam.zgysyjy.org.cn",
           url.port == 443,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // The school's gateway returns an HTTP URL on port 443 after a
            // successful callback. Upgrade this exact same-host destination
            // before WebKit loads it; every other HTTP navigation remains blocked.
            components.scheme = "https"
            if let upgraded = components.url {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: upgraded, cachePolicy: .reloadIgnoringLocalCacheData))
                return
            }
        }
        let allowed = isAllowed(navigationAction.request.url) || blankPopup
        if !allowed {
            let url = navigationAction.request.url
            let scheme = url?.scheme ?? "未知协议"
            let host = url?.host ?? "无主机"
            let port = url?.port.map(String.init) ?? "默认端口"
            let path = url?.path ?? "/"
            fail("学校跳转被阻止：\(scheme)://\(host):\(port)\(path)。请联系开发者核对学校跳转地址。")
        }
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let blankPopup = childWebViews.contains(where: { $0 === webView }) && navigationResponse.response.url?.absoluteString == "about:blank"
        decisionHandler(isAllowed(navigationResponse.response.url) || blankPopup ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        cancelExtraction()
        publish(.loading)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if bootstrapping, webView === self.webView {
            bootstrapping = false
            // Load the official session-creating entry first, then the mobile
            // page in the same ephemeral store. Its initial CAPTCHA fetch must
            // not race the request that creates the SESSION cookie.
            webView.load(URLRequest(url: configuration.loginURL, cachePolicy: .reloadIgnoringLocalCacheData))
            return
        }
        publish(.ready)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { cancelExtraction(); fail("门户页面加载失败，请重试或改用截图导入。") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { cancelExtraction(); fail("门户页面加载失败，请重试或改用截图导入。") }

    func webView(_ webView: WKWebView, createWebViewWith config: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              isAllowed(navigationAction.sourceFrame.request.url),
              navigationAction.request.url == nil || navigationAction.request.url?.absoluteString == "about:blank" || isAllowed(navigationAction.request.url) else { return nil }
        // WebKit supplies a compatible configuration sharing our ephemeral store.
        let popup = WKWebView(frame: .zero, configuration: config)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        childWebViews.append(popup)
        onPopupChange?(popup)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard childWebViews.contains(where: { $0 === webView }) else { return }
        childWebViews.removeAll(where: { $0 === webView })
        webView.stopLoading(); webView.navigationDelegate = nil; webView.uiDelegate = nil
        cancelExtraction()
        onPopupChange?(childWebViews.last)
        publish(.ready)
    }

    private static func js<T>(_ object: T) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]), let string = String(data: data, encoding: .utf8) else { return "null" }
        return string
    }

    /// Observes failures and invalidates stale CAPTCHA input, never reads its
    /// value or an authentication response, and never submits a login.
    static func loginSupportScript(handler: String) -> String {
        "const sanqianLoginHandler = \(js(handler));\n" + #"""
        (() => {
          if (location.origin !== 'https://iam.zgysyjy.org.cn' || location.pathname !== '/am/mLogin/login.html') return;
          const report = code => window.webkit.messageHandlers[sanqianLoginHandler].postMessage({kind:'loginStatus',code});
          const images = Array.from(document.querySelectorAll('img.img_code'));
          const observer = new MutationObserver(records => {
            if (!records.some(r => r.type === 'attributes' && r.attributeName === 'src')) return;
            for (const id of ['img_codes','m_img_code']) {
              const input = document.getElementById(id);
              if (input) { input.value = ''; input.dispatchEvent(new Event('input', {bubbles:true})); }
            }
            report('captchaChanged');
          });
          images.forEach(img => observer.observe(img, {attributes:true, attributeFilter:['src']}));
          const open = XMLHttpRequest.prototype.open;
          const watched = new WeakSet();
          XMLHttpRequest.prototype.open = function(method, address, ...args) {
            watched.delete(this);
            try {
              const u = new URL(address, location.href);
              if (u.origin === location.origin && ['/am/validatecode/verify.do','/am/api/auth/getRandom','/am/api/auth/module/BjcaLDAP','/am/api/auth/callbacks'].includes(u.pathname)) watched.add(this);
            } catch (_) {}
            return open.call(this, method, address, ...args);
          };
          const send = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.send = function(...args) {
            if (watched.has(this)) this.addEventListener('loadend', () => {
              if (this.status === 0 || this.status >= 400) report('requestFailed');
            }, {once:true});
            return send.apply(this, args);
          };
          window.addEventListener('error', () => report('scriptFailed'));
          window.addEventListener('unhandledrejection', () => report('scriptFailed'));
        })();
        """#
    }

    /// Internal visibility lets the offline JS harness exercise the production script.
    static func extractionScript(handler: String, allowedHosts: Set<String>) -> String {
        "const sanqianAllowedHosts = \(js(Array(allowedHosts))); const sanqianHandler = \(js(handler));\n" + #"""
        (function() {
          if (window.__sanqianScheduleHooked) return;
          if (location.protocol !== 'https:' || !sanqianAllowedHosts.includes(location.hostname.toLowerCase())) return;
          window.__sanqianScheduleHooked = true;
          const completed = new Set();
          const clean = value => String(value || '').replace(/\u00a0/g, ' ').trim();
          const safeText = cell => {
            if (cell.hidden || cell.getAttribute('aria-hidden') === 'true') return '';
            const style = window.getComputedStyle ? window.getComputedStyle(cell) : null;
            if (style && (style.display === 'none' || style.visibility === 'hidden')) return '';
            const copy = cell.cloneNode(true);
            copy.querySelectorAll('input,textarea,select,button,script,style,[hidden],[aria-hidden="true"],form,[style*="display:none"],[style*="display: none"],[style*="visibility:hidden"],[style*="visibility: hidden"]').forEach(node => node.remove());
            copy.querySelectorAll('br').forEach(node => node.replaceWith('\n'));
            return clean(copy.textContent);
          };
          const span = (cell, name, limit) => Math.min(limit, Math.max(1, parseInt(cell.getAttribute(name) || '1', 10) || 1));
          const send = (requestID, rows, truncated = false) => window.webkit.messageHandlers[sanqianHandler].postMessage({
            version:1, kind:'scheduleTables', requestID, title:'', html:'', innerText:'', rows, truncated,
            frame:{url:location.origin + location.pathname, securityOrigin:location.origin, isMainFrame:window === window.top}
          });
          window.addEventListener('message', event => {
            const value = event.data;
            let sender;
            try { sender = new URL(event.origin); } catch (_) { return; }
            if (sender.protocol !== 'https:' || !sanqianAllowedHosts.includes(sender.hostname.toLowerCase())) return;
            if (!value || value.sanqianSchedule !== 'extract' || typeof value.requestID !== 'string' || !/^[A-Fa-f0-9-]{36}$/.test(value.requestID)) return;
            if (completed.has(value.requestID)) return;
            completed.add(value.requestID);
            if (completed.size > 32) completed.delete(completed.values().next().value);
            // Access to a direct child WindowProxy does not require access to its DOM.
            for (let i = 0; i < window.frames.length; i++) {
              try { window.frames[i].postMessage(value, '*'); } catch (_) {}
            }
            let count = 0;
            const pageTables = Array.from(document.querySelectorAll('table'));
            for (const table of pageTables.slice(0, 32)) {
              if (table.querySelector('input[type="password"]')) continue;
              let truncated = pageTables.length > 32 || table.rows.length > 128;
              const rows = Array.from(table.rows || []).slice(0,128).map(row => {
                if (row.cells.length > 32) truncated = true;
                return Array.from(row.cells || []).slice(0,32).map(cell => {
                  const text = safeText(cell);
                  if (text.length > 2000) truncated = true;
                  return {text:text.slice(0,2000), rowSpan:span(cell,'rowspan',128), colSpan:span(cell,'colspan',32)};
                });
              });
              const text = rows.flat().map(cell => cell.text).join(' ');
              if (rows.length >= 2 && ((/课程名称|课程名|科目|教学科目/.test(text) && /上课|时间|地点|安排|周次/.test(text)) || /周一|星期一/.test(text) && /周二|星期二/.test(text))) {
                send(value.requestID, rows, truncated); count++;
              }
            }
            // A zero-table frame still acknowledges extraction, ending empty pages.
            if (!count) send(value.requestID, []);
          });
        })();
        """#
    }
}

@MainActor
private final class SchoolPortalMessageBridge: NSObject, WKScriptMessageHandler {
    weak var session: SchoolPortalSession?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        session?.receive(message)
    }
}
