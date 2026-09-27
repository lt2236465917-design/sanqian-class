package com.lilystudio.wheretosleepinnju

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JsPromptResult
import android.webkit.JsResult
import android.webkit.WebChromeClient
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.webkit.WebMessageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

class SchoolPortalActivity : Activity() {
    private lateinit var status: TextView
    private lateinit var guide: TextView
    private lateinit var extractButton: Button
    private lateinit var container: FrameLayout
    private lateinit var mainWebView: WebView
    private val childWebViews = mutableListOf<WebView>()
    private val handler = Handler(Looper.getMainLooper())
    private var extractionID: String? = null
    private val tables = mutableListOf<SchoolPortalFrameMessage>()
    private val observedFrames = mutableSetOf<String>()
    private var finishRunnable: Runnable? = null
    private var deadlineRunnable: Runnable? = null
    private var bootstrapping = false
    private var started = false
    private var preparing = false
    private var portalEpoch = 0
    private var backHandle: Any? = null

    private val activeWebView: WebView get() = childWebViews.lastOrNull() ?: mainWebView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        backHandle = PredictiveBack.register(this) { goBack() }
        setContentView(R.layout.activity_school_portal)
        status = findViewById(R.id.portal_status)
        guide = findViewById(R.id.portal_guide)
        extractButton = findViewById(R.id.portal_extract)
        container = findViewById(R.id.portal_web_container)
        findViewById<Button>(R.id.portal_cancel).setOnClickListener { cancel() }
        extractButton.setOnClickListener {
            if (!started) preparePortal() else requestExtraction()
        }
        refreshChrome()

        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) ||
            !WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)
        ) {
            showStatus("当前系统 WebView 过旧，无法安全读取嵌套课表页。请更新 Android System WebView 后重试。")
            return
        }

        preparePortal()
    }

    private fun preparePortal() {
        if (preparing || started || isFinishing || isDestroyed) return
        preparing = true
        val epoch = portalEpoch
        showStatus("正在清理上一次登录状态…")
        PortalStorageReset.reset(
            deleteWebStorage = { WebStorage.getInstance().deleteAllData() },
            removeAllCookies = { done ->
                CookieManager.getInstance().removeAllCookies { hadCookiesRemoved ->
                    handler.post { done(hadCookiesRemoved == true) }
                }
            },
            onReady = {
                preparing = false
                if (!portalCleanupMayOpen(epoch, portalEpoch, isFinishing, isDestroyed)) {
                    return@reset
                }
                try {
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().flush()
                    mainWebView = createWebView()
                    show(mainWebView)
                    bootstrapping = true
                    started = true
                    showStatus("")
                    refreshChrome()
                    mainWebView.loadUrl(BOOTSTRAP_URL)
                } catch (_: Exception) {
                    started = false
                    showStatus("门户未能打开。请点底部「重试」。")
                    refreshChrome()
                }
            },
            onFailure = { message ->
                preparing = false
                if (!portalCleanupMayOpen(epoch, portalEpoch, isFinishing, isDestroyed)) {
                    return@reset
                }
                started = false
                showStatus(message)
                refreshChrome()
            }
        )
    }

    override fun onBackPressed() {
        goBack()
    }

    override fun onDestroy() {
        portalEpoch += 1
        preparing = false
        PredictiveBack.unregister(this, backHandle)
        backHandle = null
        cancelExtraction()
        // Cookie wiping after WebView.destroy crashes some system WebViews and
        // takes the whole process down. The next open clears storage first.
        destroyWebViews()
        super.onDestroy()
    }

    private fun destroyWebViews() {
        val views = (childWebViews + if (this::mainWebView.isInitialized) listOf(mainWebView) else emptyList()).distinct()
        childWebViews.clear()
        for (view in views) {
            try {
                view.stopLoading()
                view.webChromeClient = null
                view.webViewClient = WebViewClient()
                (view.parent as? ViewGroup)?.removeView(view)
                view.destroy()
            } catch (_: Throwable) {
            }
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(): WebView {
        val webView = WebView(this)
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.javaScriptCanOpenWindowsAutomatically = true
        webView.settings.setSupportMultipleWindows(true)
        webView.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        webView.settings.useWideViewPort = true
        webView.settings.setSupportZoom(true)
        webView.settings.builtInZoomControls = true
        webView.settings.displayZoomControls = false
        webView.settings.userAgentString = webView.settings.userAgentString.replace("; wv", "")
        webView.settings.allowFileAccess = false
        webView.settings.allowContentAccess = false
        webView.settings.cacheMode = WebSettings.LOAD_NO_CACHE
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        WebViewCompat.addDocumentStartJavaScript(webView, LOGIN_SCRIPT + "\n" + EXTRACTION_SCRIPT, ALLOWED_ORIGINS)
        WebViewCompat.addWebMessageListener(
            webView,
            HANDLER_NAME,
            ALLOWED_ORIGINS,
            WebViewCompat.WebMessageListener { _, message, sourceOrigin, isMainFrame, _ ->
                receive(message, sourceOrigin, isMainFrame)
            }
        )
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                return handleNavigation(view, request.url)
            }

            @Deprecated("Deprecated in Java")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
                return handleNavigation(view, Uri.parse(url))
            }

            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                cancelExtraction()
            }

            override fun onPageFinished(view: WebView, url: String?) {
                if (bootstrapping && view === mainWebView) {
                    bootstrapping = false
                    view.loadUrl(LOGIN_URL)
                    return
                }
                refreshChrome()
                scheduleCredentialFill(view, url)
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceError
            ) {
                if (!request.isForMainFrame) return
                started = false
                cancelExtraction()
                showStatus("网页没打开。请确认手机能上网后点底部「重试」；也可以改用多图课表导入。")
                refreshChrome()
            }

            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                // The default return kills the app process. The system then
                // relaunches into the opening animation.
                handler.post { recoverFromRendererLoss(view) }
                return true
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean {
                val parentUrl = view.url?.let { Uri.parse(it) }
                if (!isAllowed(parentUrl) && parentUrl?.toString() != "about:blank") return false
                val popup = createWebView()
                childWebViews.add(popup)
                show(popup)
                val transport = resultMsg.obj as WebView.WebViewTransport
                transport.webView = popup
                resultMsg.sendToTarget()
                return true
            }

            override fun onCloseWindow(window: WebView) {
                closePopup(window)
            }

            override fun onJsAlert(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
                showJsDialog(message, okOnly = true, result = result, prompt = null, defaultValue = null)
                return true
            }

            override fun onJsConfirm(view: WebView, url: String?, message: String?, result: JsResult): Boolean {
                showJsDialog(message, okOnly = false, result = result, prompt = null, defaultValue = null)
                return true
            }

            override fun onJsPrompt(
                view: WebView,
                url: String?,
                message: String?,
                defaultValue: String?,
                result: JsPromptResult
            ): Boolean {
                showJsDialog(message, okOnly = false, result = null, prompt = result, defaultValue = defaultValue)
                return true
            }
        }
        return webView
    }

    private fun handleNavigation(view: WebView, uri: Uri): Boolean {
        val blankPopup = childWebViews.contains(view) && uri.toString() == "about:blank"
        if (blankPopup) return false
        when (val decision = SchoolPortalSecurity.decide(uri.toString())) {
            PortalNavigation.Allow -> return false
            is PortalNavigation.Upgrade -> {
                view.loadUrl(decision.url)
                return true
            }
            PortalNavigation.Block -> {
                val scheme = uri.scheme ?: "未知协议"
                val host = uri.host ?: "无主机"
                val port = if (uri.port == -1) "默认端口" else uri.port.toString()
                val path = uri.path ?: "/"
                showStatus("学校跳转被阻止：$scheme://$host:$port$path。请联系开发者核对学校跳转地址。")
                return true
            }
        }
    }

    private fun isAllowed(uri: Uri?): Boolean {
        if (uri == null) return false
        if (!uri.userInfo.isNullOrEmpty()) return false
        val host = uri.host ?: return false
        return SchoolPortalSecurity.allows(uri.scheme ?: "", host)
    }

    private fun show(webView: WebView) {
        container.removeAllViews()
        container.addView(
            webView,
            FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        )
    }

    private fun goBack() {
        if (!this::mainWebView.isInitialized) {
            cancel()
            return
        }
        if (activeWebView.canGoBack()) {
            activeWebView.goBack()
        } else if (childWebViews.isNotEmpty()) {
            closePopup(childWebViews.last())
        } else {
            cancel()
        }
    }

    private fun closePopup(window: WebView) {
        if (!childWebViews.remove(window)) return
        window.stopLoading()
        (window.parent as? ViewGroup)?.removeView(window)
        window.destroy()
        cancelExtraction()
        show(activeWebView)
    }

    private fun requestExtraction() {
        if (!started) return
        cancelExtraction()
        val requestID = UUID.randomUUID().toString()
        extractionID = requestID
        showStatus("正在读取课表…")
        val script = "window.postMessage({sanqianSchedule:'extract',requestID:${JSONObject.quote(requestID)}},location.origin);"
        val deadline = Runnable { finishExtraction(requestID, timedOut = true) }
        deadlineRunnable = deadline
        handler.postDelayed(deadline, 4000)
        activeWebView.evaluateJavascript(script) { _ -> }
    }

    private fun cancelExtraction() {
        finishRunnable?.let { handler.removeCallbacks(it) }
        deadlineRunnable?.let { handler.removeCallbacks(it) }
        finishRunnable = null
        deadlineRunnable = null
        extractionID = null
        tables.clear()
        observedFrames.clear()
    }

    private fun recoverFromRendererLoss(view: WebView) {
        if (isFinishing || isDestroyed) return
        cancelExtraction()
        started = false
        bootstrapping = false
        try {
            (view.parent as? ViewGroup)?.removeView(view)
            childWebViews.remove(view)
        } catch (_: Throwable) {
        }
        showStatus("学校网页已中断。请点底部「重试」。")
        refreshChrome()
    }

    private fun receive(message: WebMessageCompat, sourceOrigin: Uri, isMainFrame: Boolean) {
        try {
            receiveMessage(message, sourceOrigin, isMainFrame)
        } catch (_: Throwable) {
        }
    }

    private fun receiveMessage(message: WebMessageCompat, sourceOrigin: Uri, isMainFrame: Boolean) {
        val data = message.data ?: return
        val payload = try {
            JSONObject(data)
        } catch (_: Exception) {
            return
        }
        val host = sourceOrigin.host ?: return
        val scheme = sourceOrigin.scheme ?: return
        if (payload.optString("kind") == "loginStatus") {
            if (isMainFrame &&
                scheme.equals("https", true) &&
                host.equals("iam.zgysyjy.org.cn", true) &&
                loginPortOk(sourceOrigin) &&
                activeWebView.url?.let { Uri.parse(it).path } == "/am/mLogin/login.html"
            ) {
                when (payload.optString("code")) {
                    "captchaChanged" -> showStatus("验证码已刷新，请输入网页里当前图片中的验证码。")
                    "requestFailed" -> showStatus("学校登录请求失败，请在网页里再试一次。")
                    "scriptFailed" -> showStatus("学校登录页面执行失败，请取消后重新打开。")
                }
            }
            return
        }
        if (!SchoolPortalSecurity.allows(scheme, host)) return
        val parsed = SchoolPortalFrameMessage.fromJson(payload) ?: return
        val requestID = extractionID ?: return
        if (parsed.requestID != requestID) return
        if (parsed.rows.size > 128) return
        if (parsed.rows.any { row ->
                row.size > 32 || row.any { cell ->
                    cell.text.length > 2000 || cell.rowSpan !in 1..128 || cell.colSpan !in 1..32
                }
            }
        ) return
        val url = SchoolPortalSecurity.sanitizedURL(sourceOrigin.toString()) ?: "https://$host/"
        val trusted = SchoolPortalFrameMessage(
            version = 1,
            kind = "scheduleTables",
            requestID = requestID,
            frame = SchoolPortalFrameIdentity(
                url = url,
                securityOrigin = "https://$host:${if (sourceOrigin.port == -1) 443 else sourceOrigin.port}",
                isMainFrame = isMainFrame
            ),
            title = "",
            innerText = parsed.rows.flatten().joinToString("\n") { it.text },
            html = "",
            rows = parsed.rows,
            truncated = parsed.truncated
        )
        observedFrames.add(url)
        if (trusted.rows.isNotEmpty() && tables.none { it.rows == trusted.rows && it.frame.url == trusted.frame.url }) {
            tables.add(trusted)
        }
        finishRunnable?.let { handler.removeCallbacks(it) }
        val finish = Runnable { finishExtraction(requestID, timedOut = false) }
        finishRunnable = finish
        handler.postDelayed(finish, 800)
    }

    private fun finishExtraction(requestID: String, timedOut: Boolean) {
        if (extractionID != requestID) return
        val pageUrl = try {
            SchoolPortalSecurity.sanitizedURL(activeWebView.url)
        } catch (_: Throwable) {
            null
        }
        try {
            val parsed = SchoolScheduleParser.parse(
                tables.toList(),
                frameCount = observedFrames.size,
                sourceURL = pageUrl
            )
            val warning = if (timedOut) {
                "读取窗口已结束；未响应或仍在加载的页面需重新读取。"
            } else {
                "已汇总本次响应的表格；仍在加载的页面需重新读取。"
            }
            val result = parsed.copy(warnings = parsed.warnings + warning)
            cancelExtraction()
            if (!result.canReview) {
                showStatus(parsed.warnings.lastOrNull() ?: "当前页面没有可识别课表。请先进入「研究生综合管理 → 我的课表」，看到课表后再点底部「读取并识别」。")
                return
            }
            val payload = toJsonValue(result.toChannelMap()) as JSONObject
            val json = payload.toString()
            if (!PortalResultBus.offer(json)) {
                showStatus("这次读到的课表太长，没有带回。请分页面读取，或改用多图课表导入。")
                return
            }
            setResult(RESULT_OK, Intent().putExtra(EXTRA_RESULT, PortalResultBus.TOKEN))
            finish()
        } catch (_: Throwable) {
            PortalResultBus.clear()
            cancelExtraction()
            if (!isFinishing && !isDestroyed) {
                showStatus("读取课表失败。请留在此页，点底部「读取并识别」再试一次。")
            }
        }
    }

    private fun showStatus(message: String) {
        status.visibility = if (message.isEmpty()) View.GONE else View.VISIBLE
        status.text = message
    }

    private fun refreshChrome() {
        val url = try {
            if (started && this::mainWebView.isInitialized) activeWebView.url else null
        } catch (_: Throwable) {
            null
        }
        val login = isLoginPage(url?.let { Uri.parse(it) })
        if (!started) {
            extractButton.text = "重试"
            guide.text = "学校网页还没打开。确认手机能上网后，点底部「重试」。"
        } else if (login) {
            extractButton.text = "读取并识别"
            guide.text = "填写验证码，再点网页里的「登录」。"
        } else {
            extractButton.text = "读取并识别"
            guide.text = "进入「我的课表」，看到课程后点底部「读取并识别」。"
        }
    }

    private fun scheduleCredentialFill(view: WebView, url: String?) {
        val uri = url?.let { Uri.parse(it) } ?: return
        if (!isLoginPage(uri)) return
        handler.postDelayed({ fillSavedCredentials(view) }, 400)
        handler.postDelayed({ fillSavedCredentials(view) }, 1200)
    }

    private fun fillSavedCredentials(view: WebView) {
        if (isFinishing || !view.isAttachedToWindow) return
        val uri = view.url?.let { Uri.parse(it) } ?: return
        if (!isLoginPage(uri)) return
        try {
            ScheduleCredentialsStore.get(this).withSchoolCredentials { account, password ->
                val values = JSONArray().put(account).put(password).toString()
                val script = """
                    (() => {
                      if (location.origin !== 'https://iam.zgysyjy.org.cn' || !['/am/UI/Login','/am/mLogin/login.html'].includes(location.pathname)) return 'blocked';
                      const u = document.querySelector('input[id="login_name"],input[name="username"],input[name="loginName"],input[autocomplete="username"],input[id="username"]');
                      const p = document.querySelector('input[type="password"]');
                      if (!u || !p || !u.getClientRects().length || !p.getClientRects().length) return 'missing';
                      const v = $values;
                      const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
                      set.call(u, v[0]);
                      set.call(p, v[1]);
                      [u, p].forEach((el) => {
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                        el.dispatchEvent(new Event('change', { bubbles: true }));
                      });
                      return 'filled';
                    })()
                """.trimIndent()
                view.evaluateJavascript(script) { raw ->
                    when (raw?.trim('"')) {
                        "filled" -> showStatus("已填入本机保存的账号和密码。请填写验证码，再点网页里的「登录」。")
                        "missing" -> showStatus("没有自动填入密码。请在网页里手动输入账号和密码。")
                        "blocked" -> { }
                    }
                }
            }
        } catch (_: ScheduleCredentialsStoreError.NotFound) {
            // User will type on the page.
        } catch (_: Exception) {
            // Keep the step guide; do not surface credential details.
        }
    }

    private fun isLoginPage(uri: Uri?): Boolean {
        if (uri == null) return false
        if (uri.scheme != "https" || uri.host != "iam.zgysyjy.org.cn") return false
        if (!loginPortOk(uri)) return false
        return uri.path in listOf("/am/UI/Login", "/am/mLogin/login.html")
    }

    private fun loginPortOk(uri: Uri): Boolean = uri.port == -1 || uri.port == 443

    private fun cancel() {
        PortalResultBus.clear()
        setResult(RESULT_CANCELED)
        finish()
    }

    private fun showJsDialog(
        message: String?,
        okOnly: Boolean,
        result: JsResult?,
        prompt: JsPromptResult?,
        defaultValue: String?
    ) {
        val builder = AlertDialog.Builder(this).setMessage(message ?: "")
        if (prompt != null) {
            val input = android.widget.EditText(this)
            input.setText(defaultValue ?: "")
            builder.setView(input)
            builder.setPositiveButton(android.R.string.ok) { _, _ -> prompt.confirm(input.text.toString()) }
            builder.setNegativeButton(android.R.string.cancel) { _, _ -> prompt.cancel() }
            builder.setOnCancelListener { prompt.cancel() }
        } else {
            builder.setPositiveButton(android.R.string.ok) { _, _ -> result?.confirm() }
            if (!okOnly) builder.setNegativeButton(android.R.string.cancel) { _, _ -> result?.cancel() }
            builder.setOnCancelListener { result?.cancel() }
        }
        builder.show()
    }

    companion object {
        const val EXTRA_RESULT = "sanqian.portal.result"
        const val HANDLER_NAME = "sanqianSchoolSchedule"
        const val LOGIN_URL = "https://iam.zgysyjy.org.cn/am/mLogin/login.html"
        const val BOOTSTRAP_URL = "https://iam.zgysyjy.org.cn/am/UI/Login"
        val ALLOWED_ORIGINS = setOf(
            "https://iam.zgysyjy.org.cn",
            "https://access.zgysyjy.org.cn",
            "https://wxt.zgysyjy.org.cn",
            "https://wxt.zgysyjy.org.cn:7792"
        )

        private val LOGIN_SCRIPT = """
            const sanqianLoginHandler = "$HANDLER_NAME";
            (() => {
              if (location.origin !== 'https://iam.zgysyjy.org.cn' || location.pathname !== '/am/mLogin/login.html') return;
              const report = code => {
                if (window.sanqianSchoolSchedule && window.sanqianSchoolSchedule.postMessage) {
                  window.sanqianSchoolSchedule.postMessage(JSON.stringify({kind:'loginStatus',code}));
                }
              };
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
        """.trimIndent()

        private val EXTRACTION_SCRIPT = """
            const sanqianAllowedHosts = ["iam.zgysyjy.org.cn","access.zgysyjy.org.cn","wxt.zgysyjy.org.cn"];
            const sanqianHandler = "$HANDLER_NAME";
            (function() {
              if (window.__sanqianScheduleHooked) return;
              if (location.protocol !== 'https:' || !sanqianAllowedHosts.includes(location.hostname.toLowerCase())) return;
              window.__sanqianScheduleHooked = true;
              const completed = new Set();
              const clean = value => String(value || '').replace(/\u00a0/g, ' ').trim();
              const safeText = (cell, view) => {
                try {
                  if (!cell) return '';
                  if (cell.hidden || cell.getAttribute('aria-hidden') === 'true') return '';
                  const owner = view || window;
                  const style = owner.getComputedStyle ? owner.getComputedStyle(cell) : null;
                  if (style && (style.display === 'none' || style.visibility === 'hidden')) return '';
                  const copy = cell.cloneNode(true);
                  copy.querySelectorAll('input,textarea,select,button,script,style,[hidden],[aria-hidden="true"],form,[style*="display:none"],[style*="display: none"],[style*="visibility:hidden"],[style*="visibility: hidden"]').forEach(node => node.remove());
                  copy.querySelectorAll('br').forEach(node => node.replaceWith('\n'));
                  return clean(copy.textContent);
                } catch (_) { return ''; }
              };
              const span = (cell, name, limit) => Math.min(limit, Math.max(1, parseInt(cell.getAttribute(name) || '1', 10) || 1));
              const weight = list => list.reduce((n, row) => n + row.reduce((m, cell) => m + String(cell.text || '').length + 24, 48), 0);
              const send = (requestID, rows, truncated = false) => {
                let payloadRows = rows;
                let flag = !!truncated;
                while (weight(payloadRows) > 48000 && payloadRows.length > 1) {
                  flag = true;
                  payloadRows = payloadRows.slice(0, Math.max(1, Math.floor(payloadRows.length / 2)));
                }
                if (weight(payloadRows) > 48000) {
                  flag = true;
                  payloadRows = payloadRows.slice(0, 1).map(row => row.slice(0, 8).map(cell => ({text: String(cell.text || '').slice(0, 400), rowSpan: cell.rowSpan, colSpan: cell.colSpan})));
                }
                if (window.sanqianSchoolSchedule && window.sanqianSchoolSchedule.postMessage) {
                  window.sanqianSchoolSchedule.postMessage(JSON.stringify({
                    version:1, kind:'scheduleTables', requestID, title:'', html:'', innerText:'', rows: payloadRows, truncated: flag,
                    frame:{url:location.origin + location.pathname, securityOrigin:location.origin, isMainFrame:window === window.top}
                  }));
                }
              };
              const publishDocument = (doc, view, requestID) => {
                let count = 0;
                const pageTables = Array.from(doc.querySelectorAll('table'));
                for (const table of pageTables.slice(0, 32)) {
                  if (table.querySelector('input[type="password"]')) continue;
                  let truncated = pageTables.length > 32 || table.rows.length > 128;
                  const rows = Array.from(table.rows || []).slice(0,128).map(row => {
                    if (row.cells.length > 32) truncated = true;
                    return Array.from(row.cells || []).slice(0,32).map(cell => {
                      const text = safeText(cell, view);
                      if (text.length > 2000) truncated = true;
                      return {text:text.slice(0,2000), rowSpan:span(cell,'rowspan',128), colSpan:span(cell,'colspan',32)};
                    });
                  });
                  const text = rows.flat().map(cell => cell.text).join(' ');
                  if (rows.length >= 2 && ((/课程名称|课程名|科目|教学科目/.test(text) && /上课|时间|地点|安排|周次/.test(text)) || /周一|星期一/.test(text) && /周二|星期二/.test(text))) {
                    send(requestID, rows, truncated); count++;
                  }
                }
                return count;
              };
              window.addEventListener('message', event => {
                try {
                  const value = event.data;
                  let sender;
                  try { sender = new URL(event.origin); } catch (_) { return; }
                  if (sender.protocol !== 'https:' || !sanqianAllowedHosts.includes(sender.hostname.toLowerCase())) return;
                  if (!value || value.sanqianSchedule !== 'extract' || typeof value.requestID !== 'string' || !/^[A-Fa-f0-9-]{36}$/.test(value.requestID)) return;
                  const depth = Number(value.depth) || 0;
                  if (depth > 6) return;
                  if (completed.has(value.requestID)) return;
                  completed.add(value.requestID);
                  if (completed.size > 32) completed.delete(completed.values().next().value);
                  const seen = new Set();
                  const visit = (win, level) => {
                    if (!win || level > 6 || seen.has(win)) return 0;
                    seen.add(win);
                    let count = 0;
                    const doc = win === window ? document : (() => { try { return win.document; } catch (_) { return null; } })();
                    if (doc && doc.querySelectorAll) count += publishDocument(doc, win, value.requestID);
                    let n = 0;
                    try { n = win.frames.length; } catch (_) { n = 0; }
                    for (let i = 0; i < n && i < 32; i++) {
                      let child = null;
                      try { child = win.frames[i]; } catch (_) { continue; }
                      if (!child) continue;
                      let readable = false;
                      try { readable = child !== window && !!(child.document && child.document.querySelectorAll); } catch (_) { readable = false; }
                      let found = 0;
                      if (readable) found = visit(child, level + 1);
                      if (!readable || !found) { try { child.postMessage({sanqianSchedule:'extract', requestID: value.requestID, depth: level + 1}, '*'); } catch (_) {} }
                      count += found;
                    }
                    return count;
                  };
                  const count = visit(window, depth);
                  if (!count) send(value.requestID, []);
                } catch (_) {}
              });
            })();
        """.trimIndent()
    }
}
