import Flutter
import UIKit
import WebKit
import WidgetKit

@MainActor
final class ScheduleImportPlugin: NSObject, FlutterPlugin {
    private var recognition: Task<Void, Never>?
    private weak var presenter: UIViewController?
    init(presenter: UIViewController?) { self.presenter = presenter }
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "sanqian/schedule_import", binaryMessenger: registrar.messenger())
        let plugin = ScheduleImportPlugin(presenter: nil)
        registrar.addMethodCallDelegate(plugin, channel: channel)
    }
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let store = ScheduleCredentialsStore.shared
        do {
            switch call.method {
            case "hasAPIKey": result(try store.hasDeepSeekAPIKey())
            case "saveAPIKey": try store.saveDeepSeekAPIKey(args["key"] as? String ?? ""); result(true)
            case "deleteAPIKey": try store.deleteDeepSeekAPIKey(); result(true)
            case "schoolAccount":
                if let info = try store.schoolAccountMetadata() { result(["account": info.account, "accountLocalId": info.accountLocalId]) }
                else { result(nil) }
            case "saveSchoolAccount":
                let info = try store.saveSchoolCredentials(account: args["account"] as? String ?? "", password: args["password"] as? String ?? "")
                result(["account": info.account, "accountLocalId": info.accountLocalId])
            case "deleteSchoolAccount": try store.deleteSchoolCredentials(); result(true)
            case "loadLegacyJwCredentials":
                if let saved = try store.loadLegacyJw() { result(["username": saved.username, "password": saved.password]) }
                else { result(nil) }
            case "saveLegacyJwCredentials":
                try store.saveLegacyJw(username: args["username"] as? String ?? "", password: args["password"] as? String ?? "")
                result(true)
            case "deleteLegacyJwCredentials":
                try store.deleteLegacyJw(); result(true)
            case "openPortal":
                let once = OnceFlutterResult(result)
                let controller = SchoolPortalController()
                controller.completion = { once.send($0) }
                guard let host = currentPresenter() else {
                    once.send(FlutterError(code: "schedule_import", message: ImportBridgeError.unavailable.errorDescription, details: nil))
                    return
                }
                let navigation = UINavigationController(rootViewController: controller)
                navigation.isModalInPresentation = true
                host.present(navigation, animated: true)
            case "cancelRecognition": recognition?.cancel(); result(true)
            case "recognizeText":
                guard recognition == nil else { throw ImportBridgeError.busy }
                let text = args["text"] as? String ?? ""
                recognition = Task { [weak self] in
                    defer { self?.recognition = nil }
                    do {
                        guard let key = try store.loadDeepSeekAPIKey() else { throw DeepSeekTimetableClientError.missingAPIKey }
                        let output = try await DeepSeekTimetableClient(apiKey: key).recognize(text: text)
                        try Task.checkCancellation()
                        result(try JSONSerialization.jsonObject(with: Data(output.jsonText.utf8)))
                    } catch { result(FlutterError(code: "recognition", message: error.localizedDescription, details: nil)) }
                }
            case "recognizePhotos", "recognizePhotosWithOCR":
                guard recognition == nil else { throw ImportBridgeError.busy }
                let paths = args["paths"] as? [String] ?? []
                guard !paths.isEmpty, paths.count <= 20 else { throw ImportBridgeError.images }
                let useOCR = call.method == "recognizePhotosWithOCR"
                recognition = Task { [weak self] in
                    defer { self?.recognition = nil }
                    do {
                        var images: [UIImage] = []
                        for path in paths {
                            try Task.checkCancellation()
                            guard let image = UIImage(contentsOfFile: path) else { throw ImportBridgeError.images }
                            images.append(image)
                        }
                        guard let key = try store.loadDeepSeekAPIKey() else { throw DeepSeekTimetableClientError.missingAPIKey }
                        let input = try images.map { image -> AIImportImage in
                            guard let bytes = image.jpegData(compressionQuality: 0.95) else { throw ImportBridgeError.images }
                            return AIImportImage(data: bytes)
                        }
                        let pages: [VisionTimetablePage]?
                        if useOCR {
                            pages = try await VisionTimetableRecognizer().recognize(images: images)
                        } else { pages = nil }
                        try Task.checkCancellation()
                        let output = try await DeepSeekTimetableClient(apiKey: key).recognize(images: input, ocrPages: pages)
                        let object = try JSONSerialization.jsonObject(with: Data(output.jsonText.utf8))
                        try Task.checkCancellation()
                        result(object)
                    } catch { result(FlutterError(code: "recognition", message: error.localizedDescription, details: nil)) }
                }
            case "clearLegacyReminders":
                ScheduleReminderScheduler.shared.clearLegacy { result(true) }
            case "syncDerivedData":
                var widgetError: String?
                if let group = Bundle.main.object(forInfoDictionaryKey: "ScheduleAppGroup") as? String,
                   let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                    do {
                        // Only the explicit occurrence schema crosses to the extension.
                        let safe: [String:Any] = ["schemaVersion": 1, "tableId": args["tableId"] ?? 0,
                            "revision": args["revision"] ?? "", "generatedAtMs": args["generatedAtMs"] ?? 0,
                            "occurrences": args["occurrences"] ?? []]
                        try JSONSerialization.data(withJSONObject: safe).write(to: folder.appendingPathComponent("personal-schedule.json"), options: .atomic)
                        if #available(iOS 14.0, *) { WidgetCenter.shared.reloadTimelines(ofKind: "SanqianPersonalSchedule") }
                    } catch { widgetError = "共享课表写入失败" }
                } else { widgetError = "App Group 尚不可用" }
                result(["widgetError": widgetError as Any? ?? NSNull()])
            default: result(FlutterMethodNotImplemented)
            }
        } catch { result(FlutterError(code: "schedule_import", message: error.localizedDescription, details: nil)) }
    }

    private func currentPresenter() -> UIViewController? {
        if let presenter { return Self.topMost(presenter) }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let snapshots = scenes.map { scene in
            PortalSceneSnapshot(
                activation: Self.activation(scene.activationState),
                windows: scene.windows.map { window in
                    PortalWindowSnapshot(
                        isKey: window.isKeyWindow,
                        hasRoot: window.rootViewController != nil,
                        presentedDepth: Self.depth(window.rootViewController),
                        ownsCaller: Self.containsFlutter(window.rootViewController)
                    )
                }
            )
        }
        guard let choice = PortalPresenterResolver.choose(snapshots),
              scenes.indices.contains(choice.sceneIndex) else { return nil }
        let windows = scenes[choice.sceneIndex].windows
        guard windows.indices.contains(choice.windowIndex) else { return nil }
        return Self.controller(windows[choice.windowIndex].rootViewController, depth: choice.presentedDepth)
    }

    private static func activation(_ state: UIScene.ActivationState) -> String {
        switch state {
        case .foregroundActive: return "foregroundActive"
        case .foregroundInactive: return "foregroundInactive"
        case .background: return "background"
        case .unattached: return "unattached"
        @unknown default: return "unattached"
        }
    }

    private static func containsFlutter(_ controller: UIViewController?) -> Bool {
        guard let controller else { return false }
        if controller is FlutterViewController { return true }
        if containsFlutter(controller.presentedViewController) { return true }
        return controller.children.contains { containsFlutter($0) }
    }

    private static func depth(_ controller: UIViewController?) -> Int {
        var depth = 0
        var current = controller
        while current?.presentedViewController != nil {
            depth += 1
            current = current?.presentedViewController
        }
        return depth
    }

    private static func controller(_ root: UIViewController?, depth: Int) -> UIViewController? {
        var current = root
        for _ in 0..<depth {
            guard let next = current?.presentedViewController else { break }
            current = next
        }
        return current
    }

    private static func topMost(_ controller: UIViewController) -> UIViewController {
        var current = controller
        while let next = current.presentedViewController { current = next }
        return current
    }
}

private final class OnceFlutterResult {
    private var sent = false
    private let sendResult: FlutterResult
    init(_ result: @escaping FlutterResult) { sendResult = result }
    func send(_ value: Any?) {
        guard !sent else { return }
        sent = true
        sendResult(value)
    }
}
private enum ImportBridgeError: LocalizedError {
    case unavailable, busy, images
    var errorDescription: String? {
        switch self {
        case .unavailable: return "当前无法打开学校门户"
        case .busy: return "正在识别，请先取消或等待完成"
        case .images: return "请选择 1–20 张可读取的课表图片"
        }
    }
}

@MainActor
private final class SchoolPortalController: UIViewController {
    var completion: FlutterResult?
    private let status = UILabel()
    private let container = UIView()
    private let session = SchoolPortalSession(configuration: SchoolPortalConfiguration(
        loginURL: URL(string: "https://iam.zgysyjy.org.cn/am/mLogin/login.html")!,
        allowedHosts: ["iam.zgysyjy.org.cn", "access.zgysyjy.org.cn", "wxt.zgysyjy.org.cn"],
        sessionBootstrapURL: URL(string: "https://iam.zgysyjy.org.cn/am/UI/Login")!))
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "学校门户"
        view.backgroundColor = .systemBackground
        status.numberOfLines = 3
        status.font = .systemFont(ofSize: 12)
        status.text = "请登录后进入“我的课表”，读取后由 AI 识别，核对再保存。"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "读取并识别", style: .done, target: self, action: #selector(extract))
        let fill = UIButton(type: .system)
        fill.setTitle("填入已保存账号", for: .normal)
        fill.addTarget(self, action: #selector(fillCredentials), for: .touchUpInside)
        let back = UIButton(type: .system)
        back.setTitle("返回上页／关闭弹窗", for: .normal)
        back.addTarget(self, action: #selector(goBack), for: .touchUpInside)
        let reload = UIButton(type: .system)
        reload.setTitle("刷新页面", for: .normal)
        reload.addTarget(self, action: #selector(reloadPage), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [fill,back,reload])
        [fill,back,reload].forEach { $0.titleLabel?.font = .systemFont(ofSize: 12); $0.titleLabel?.numberOfLines = 2 }
        buttons.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [status, buttons, container])
        stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo:view.leadingAnchor, constant:12),
            stack.trailingAnchor.constraint(equalTo:view.trailingAnchor, constant:-12),
            stack.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor)])
        show(session.webView)
        session.onPopupChange = { [weak self] popup in guard let self else { return }; self.show(popup ?? self.session.webView) }
        session.onStateChange = { [weak self] state in
            self?.status.text = state.errorMessage ?? (state.phase == .extracting ? "正在读取课表…" : "请进入“我的课表”后读取并进行 AI 识别；验证码在网页完成。")
        }
        session.onParseResult = { [weak self] parsed in
            guard let self, parsed.canReview else { return }
            let courses = parsed.drafts.map { draft -> [String:Any] in
                var meeting: [String:Any] = ["location": draft.location, "sourceReference": draft.rawText,
                    "raw": ["sourceURL": draft.sourceURL ?? "", "sourceText":draft.rawText, "startPeriod":draft.startPeriod as Any? ?? NSNull(), "endPeriod":draft.endPeriod as Any? ?? NSNull()]]
                meeting["weekday"] = draft.weekday; meeting["weeks"] = draft.weeks
                meeting["startMinute"] = draft.startMinutes; meeting["endMinute"] = draft.endMinutes
                var course: [String:Any] = ["name":draft.title,"teacher":draft.teacher,"meetings":[meeting]]
                course["courseCode"] = draft.courseCode; course["section"] = draft.classCode
                course["pendingReason"] = draft.pendingReason
                return course
            }
            self.finish(["courses":courses, "warnings":parsed.warnings, "timetableText":parsed.timetableText as Any? ?? NSNull()])
        }
        session.start()
    }
    private func show(_ webView: WKWebView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(webView)
        NSLayoutConstraint.activate([webView.topAnchor.constraint(equalTo:container.topAnchor),webView.bottomAnchor.constraint(equalTo:container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo:container.leadingAnchor),webView.trailingAnchor.constraint(equalTo:container.trailingAnchor)])
    }
    @objc private func extract() { session.requestExtraction() }
    @objc private func reloadPage() { session.activeWebView.reload() }
    @objc private func goBack() { if session.activeWebView.canGoBack { session.activeWebView.goBack() } else { session.closePopup() } }
    @objc private func cancel() { finish(nil) }
    private func finish(_ value: Any?) {
        let callback = completion; completion = nil; session.stop()
        dismiss(animated:true) { callback?(value) }
    }
    @objc private func fillCredentials() {
        let webView = session.activeWebView
        guard let url = webView.url, url.scheme == "https", url.host == "iam.zgysyjy.org.cn",
              ["/am/UI/Login", "/am/mLogin/login.html"].contains(url.path), url.port == nil || url.port == 443 else {
            status.text = "仅在学校 IAM 登录页允许填入凭据。"; return
        }
        do {
            try ScheduleCredentialsStore.shared.withSchoolCredentials { account, password in
                let values = String(data: try JSONSerialization.data(withJSONObject: [account,password]), encoding:.utf8)!
                let script = """
                (() => {
                  if(location.origin !== 'https://iam.zgysyjy.org.cn' || !['/am/UI/Login','/am/mLogin/login.html'].includes(location.pathname)) return false;
                  const u=document.querySelector('input[id="login_name"],input[name="username"],input[name="loginName"],input[autocomplete="username"],input[id="username"]');
                  const p=document.querySelector('input[type="password"]');
                  if(!u||!p||!u.getClientRects().length||!p.getClientRects().length) return false;
                  const v=\(values), set=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set;
                  [u,p].forEach((el,i)=>{set.call(el,v[i]);el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));});
                  return true;
                })()
                """
                webView.evaluateJavaScript(script) { [weak self] value, _ in
                    self?.status.text = value as? Bool == true ? "已填入，请在网页完成登录。" : "未找到登录表单，请在网页手动输入。"
                }
            }
        } catch { status.text = error.localizedDescription }
    }
}
