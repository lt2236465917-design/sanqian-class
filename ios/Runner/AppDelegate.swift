import UIKit
import Flutter
import AVFoundation

/// Full-screen aspect-fit player. The view owns the layer geometry; assigning
/// `playerLayer.frame` here shifts the picture into the bottom-right corner.
private final class MascotSplashPlayerView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

  init(player: AVPlayer) {
    super.init(frame: .zero)
    backgroundColor = .clear
    isOpaque = false
    isUserInteractionEnabled = false
    playerLayer.player = player
    playerLayer.videoGravity = .resizeAspect
    playerLayer.backgroundColor = UIColor.white.cgColor
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Close-up poster stays above the player for 0.5s after it is actually
/// visible, then the clip continues underneath. The player layer is black
/// until its first frame, so the poster also covers that gap.
private final class MascotSplashOverlay: UIView {
  let playerView: MascotSplashPlayerView
  private let posterView: UIImageView
  private let skipButton = UIButton(type: .system)
  private let player: AVPlayer
  private var didRevealVideo = false
  private var revealCheckScheduled = false
  private var didLogMisaligned = false
  private var visibleAt: Date?
  private var readyObservation: NSKeyValueObservation?
  private var playbackObservation: NSKeyValueObservation?
  var onSkip: (() -> Void)?
  var onReveal: (() -> Void)?
  var onFadeFinished: (() -> Void)?

  init(frame: CGRect, player: AVPlayer) {
    self.player = player
    playerView = MascotSplashPlayerView(player: player)
    posterView = UIImageView(image: UIImage(named: "MascotSplashPoster"))
    super.init(frame: frame)
    backgroundColor = .white
    isOpaque = true
    clipsToBounds = true
    autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overrideUserInterfaceStyle = .light

    playerView.frame = bounds
    posterView.frame = bounds
    posterView.contentMode = .scaleAspectFit
    posterView.backgroundColor = .white
    posterView.isOpaque = true
    posterView.clipsToBounds = true
    posterView.isUserInteractionEnabled = false
    posterView.overrideUserInterfaceStyle = .light

    skipButton.setTitle("跳过", for: .normal)
    skipButton.setTitleColor(.darkGray, for: .normal)
    skipButton.titleLabel?.font = .systemFont(ofSize: 15)
    skipButton.backgroundColor = UIColor.white.withAlphaComponent(0.9)
    skipButton.layer.cornerRadius = 8
    skipButton.accessibilityLabel = "跳过开屏动画"
    skipButton.addTarget(self, action: #selector(skipTapped), for: .touchUpInside)

    addSubview(posterView)
    addSubview(skipButton)

    readyObservation = playerView.playerLayer.observe(\.isReadyForDisplay, options: [.new]) {
      [weak self] layer, _ in
      guard layer.isReadyForDisplay else { return }
      DispatchQueue.main.async { self?.scheduleRevealCheck() }
    }
    playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async { self?.scheduleRevealCheck() }
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit {
    readyObservation?.invalidate()
    playbackObservation?.invalidate()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    playerView.frame = bounds
    posterView.frame = bounds
    skipButton.frame = CGRect(
      x: bounds.width - 76,
      y: max(16, safeAreaInsets.top + 6),
      width: 64,
      height: 40
    )
  }

  /// Starts the 0.5s hold. Call this when the poster is on screen, not while
  /// the system launch card is still covering it.
  func noteBecameVisible() {
    guard visibleAt == nil else { return }
    visibleAt = Date()
    NSLog("[MascotSplash] Poster hold started")
    scheduleRevealCheck()
  }

  func play() {
    if playerView.superview == nil {
      insertSubview(playerView, at: 0)
      playerView.frame = bounds
      playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    let mediaTime = player.currentTime().seconds
    if mediaTime.isFinite, mediaTime > 0.05 {
      player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
        self?.player.play()
        self?.scheduleRevealCheck()
      }
    } else {
      player.play()
      scheduleRevealCheck()
    }
  }

  private func scheduleRevealCheck() {
    guard !didRevealVideo, !revealCheckScheduled else { return }
    revealCheckScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      self?.revealCheckScheduled = false
      self?.revealVideoIfAdvancing()
    }
  }

  /// Poster and square aspect-fit video share this rectangle.
  private func centeredVideoRect() -> CGRect {
    let side = min(bounds.width, bounds.height)
    return CGRect(
      x: (bounds.width - side) / 2,
      y: (bounds.height - side) / 2,
      width: side,
      height: side
    )
  }

  private func videoIsCentered() -> Bool {
    guard playerView.playerLayer.isReadyForDisplay else { return false }
    let actual = playerView.playerLayer.videoRect
    let expected = centeredVideoRect()
    guard actual.width > 2, actual.height > 2 else { return false }
    return abs(actual.minX - expected.minX) < 8
      && abs(actual.minY - expected.minY) < 8
      && abs(actual.width - expected.width) < 8
      && abs(actual.height - expected.height) < 8
  }

  private func revealVideoIfAdvancing() {
    guard !didRevealVideo else { return }
    let mediaTime = player.currentTime().seconds
    let heldLongEnough = visibleAt.map { Date().timeIntervalSince($0) >= 0.5 } ?? false
    let advancing = player.timeControlStatus == .playing
      && player.rate > 0
      && mediaTime.isFinite
      && mediaTime >= 0.08
    guard heldLongEnough, advancing, videoIsCentered() else {
      if advancing, !didLogMisaligned {
        didLogMisaligned = true
        NSLog(
          "[MascotSplash] holding poster; videoRect=%@ expected=%@",
          NSCoder.string(for: playerView.playerLayer.videoRect),
          NSCoder.string(for: centeredVideoRect())
        )
      }
      scheduleRevealCheck()
      return
    }
    NSLog(
      "[MascotSplash] reveal at %.3fs videoRect=%@ bounds=%@",
      mediaTime,
      NSCoder.string(for: playerView.playerLayer.videoRect),
      NSCoder.string(for: bounds)
    )
    didRevealVideo = true
    fadePoster()
  }

  private func fadePoster() {
    onReveal?()
    UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
      self.posterView.alpha = 0
    } completion: { [weak self] _ in
      self?.posterView.isHidden = true
      self?.onFadeFinished?()
    }
  }

  @objc private func skipTapped() { onSkip?() }
}

import WidgetKit
import ActivityKit
import EventKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var widgetDataChannel: FlutterMethodChannel?
  private var scheduleNavigationChannel: FlutterMethodChannel?
  private var settingsChannel: FlutterMethodChannel?
  private var mascotSplashPosterHost: UIView?
  private var mascotSplashChannel: FlutterMethodChannel?
  private var didReleaseFlutterFrame = false
  private weak var mascotFlutterController: FlutterViewController?
  private var mascotSplashWindow: UIWindow?
  private var mascotSplashOverlay: MascotSplashOverlay?
  private var mascotSplashPlayer: AVPlayer?
  private var mascotSplashEndObserver: NSObjectProtocol?
  private var mascotSplashStatusObservation: NSKeyValueObservation?
  private var mascotSplashTimeout: DispatchWorkItem?
  private var mascotSplashItemReady = false
  private var mascotSplashPlaybackRequested = false
  private var mascotSplashPlaybackStarted = false
  private let calendarPermissionStore = EKEventStore()
  private let widgetSharingEnabled =
    Bundle.main.object(forInfoDictionaryKey: "ChaoxiWidgetsEnabled") as? Bool ?? false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = registrar(forPlugin: "ScheduleImport") {
      ScheduleImportPlugin.register(with: registrar)
    }
    if let registrar = registrar(forPlugin: "PersonalSettings") {
      settingsChannel = FlutterMethodChannel(
        name: "sanqian/settings", binaryMessenger: registrar.messenger()
      )
      settingsChannel?.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "requestCalendarAccess":
          guard let self = self else { result(false); return }
          let completion: (Bool, Error?) -> Void = { granted, error in
            DispatchQueue.main.async {
              if let error = error {
                result(FlutterError(code: "calendar_permission", message: error.localizedDescription, details: nil))
              } else { result(granted) }
            }
          }
          if #available(iOS 17.0, *) {
            self.calendarPermissionStore.requestFullAccessToEvents(completion: completion)
          } else {
            self.calendarPermissionStore.requestAccess(to: .event, completion: completion)
          }
        case "calendarHasAccess", "calendarList", "calendarCreate", "calendarEvents", "calendarSaveEvent", "calendarDeleteEvent":
          self?.handleCalendarCall(call, result: result)
        case "openAppSettings":
          guard let url = URL(string: UIApplication.openSettingsURLString) else { result(false); return }
          UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    if let registrar = registrar(forPlugin: "ScheduleNavigation") {
      registrar.register(
        ScheduleTabBarFactory(messenger: registrar.messenger()),
        withId: "chaoxi/schedule_tab_bar"
      )
      scheduleNavigationChannel = FlutterMethodChannel(
        name: "chaoxi/schedule_navigation", binaryMessenger: registrar.messenger()
      )
      scheduleNavigationChannel?.setMethodCallHandler { call, result in
        guard call.method == "isSupported" else {
          result(FlutterMethodNotImplemented)
          return
        }
        if #available(iOS 26.0, *) { result(true) } else { result(false) }
      }
    }

    // Set up widget data method channel
    setupWidgetDataChannel()
    if widgetSharingEnabled { setupSystemTimeChangeObserver() }

    let didFinishLaunching = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupMascotSplashChannel()
    showMascotLaunchAnimationIfAvailable()
    return didFinishLaunching
  }

  private func setupMascotSplashChannel() {
    guard let registrar = registrar(forPlugin: "MascotSplash") else { return }
    let channel = FlutterMethodChannel(
      name: "sanqian/mascot_splash", binaryMessenger: registrar.messenger()
    )
    mascotSplashChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "startPlayback" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.requestMascotLaunchPlayback()
      result(nil)
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    NSLog("[MascotSplash] didBecomeActive")
    // Hand Flutter a frame now so iOS can drop the white launch card.
    releaseFlutterFrame()
    mascotSplashOverlay?.noteBecameVisible()
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    dismissMascotLaunchAnimation()
    super.applicationDidEnterBackground(application)
  }

  private func showMascotLaunchAnimationIfAvailable() {
    guard mascotSplashWindow == nil, let appWindow = window else { return }
    let flutterAssets = Bundle.main.bundleURL
      .appendingPathComponent("Frameworks/App.framework/flutter_assets", isDirectory: true)
    let videoURL = flutterAssets.appendingPathComponent("res/mascot/cold-start-splash.mp4")
    guard FileManager.default.fileExists(atPath: videoURL.path) else {
      releaseFlutterFrame()
      return
    }

    appWindow.backgroundColor = .white
    if let flutterController = appWindow.rootViewController as? FlutterViewController {
      mascotFlutterController = flutterController
      flutterController.isViewOpaque = false
      flutterController.view.backgroundColor = .white
    }

    let scene = appWindow.windowScene
      ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    let screenBounds = scene?.screen.bounds ?? appWindow.bounds
    let splashWindow: UIWindow
    if let scene {
      splashWindow = UIWindow(windowScene: scene)
    } else {
      splashWindow = UIWindow(frame: screenBounds)
    }
    splashWindow.frame = screenBounds
    splashWindow.windowLevel = .alert + 1
    splashWindow.backgroundColor = .white
    splashWindow.overrideUserInterfaceStyle = .light

    let item = AVPlayerItem(url: videoURL)
    item.preferredForwardBufferDuration = 0
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    player.automaticallyWaitsToMinimizeStalling = false
    mascotSplashPlayer = player
    // Buffer under the poster. The poster itself stays 0.5s after it is visible.
    requestMascotLaunchPlayback()
    mascotSplashEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main
    ) { [weak self] _ in
      self?.dismissMascotLaunchAnimation()
    }
    mascotSplashStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch item.status {
        case .readyToPlay:
          self.mascotSplashItemReady = true
          self.startMascotLaunchPlaybackIfRequested()
        case .failed:
          NSLog("[MascotSplash] Video failed: %@", item.error?.localizedDescription ?? "unknown")
          self.dismissMascotLaunchAnimation()
        case .unknown:
          break
        @unknown default:
          break
        }
      }
    }

    let timeout = DispatchWorkItem { [weak self] in
      NSLog("[MascotSplash] Timeout, dismissing")
      self?.dismissMascotLaunchAnimation()
    }
    mascotSplashTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

    // Poster on a screen-sized window. A player inside the Flutter view is cropped.
    let host = UIViewController()
    host.view.backgroundColor = .white
    host.overrideUserInterfaceStyle = .light
    let overlay = MascotSplashOverlay(frame: screenBounds, player: player)
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.onSkip = { [weak self] in self?.dismissMascotLaunchAnimation() }
    overlay.onReveal = { [weak self] in
      self?.releaseFlutterFrame()
    }
    overlay.onFadeFinished = { [weak self] in
      self?.mascotSplashPosterHost?.removeFromSuperview()
      self?.mascotSplashPosterHost = nil
    }
    host.view.addSubview(overlay)
    splashWindow.rootViewController = host
    splashWindow.isHidden = false
    mascotSplashWindow = splashWindow
    mascotSplashOverlay = overlay
    overlay.layoutIfNeeded()
    // The system white card stays up until the key window commits a frame.
    splashWindow.makeKeyAndVisible()
    CATransaction.flush()
    releaseFlutterFrame()
    if UIApplication.shared.applicationState == .active {
      overlay.noteBecameVisible()
    }
    NSLog(
      "[MascotSplash] Splash window %@ hidden=%d",
      NSCoder.string(for: overlay.bounds),
      splashWindow.isHidden
    )
  }

  @objc private func skipMascotLaunchAnimation() {
    dismissMascotLaunchAnimation()
  }

  private func startMascotLaunchPlayback() {
    guard !mascotSplashPlaybackStarted, mascotSplashOverlay != nil else { return }
    mascotSplashPlaybackStarted = true
    mascotSplashWindow?.isHidden = false
    mascotSplashOverlay?.play()
  }

  private func requestMascotLaunchPlayback() {
    mascotSplashPlaybackRequested = true
    startMascotLaunchPlaybackIfRequested()
  }

  private func startMascotLaunchPlaybackIfRequested() {
    guard mascotSplashItemReady, mascotSplashPlaybackRequested else { return }
    startMascotLaunchPlayback()
  }

  /// Lets Flutter draw the home screen. Waits until the app is active so the
  /// Dart side is listening, then repeats once in case the first call was early.
  private func releaseFlutterFrame() {
    guard UIApplication.shared.applicationState == .active else { return }
    guard !didReleaseFlutterFrame else { return }
    didReleaseFlutterFrame = true
    mascotFlutterController?.isViewOpaque = true
    mascotSplashChannel?.invokeMethod("releaseFirstFrame", arguments: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      self?.mascotSplashChannel?.invokeMethod("releaseFirstFrame", arguments: nil)
    }
  }

  private func dismissMascotLaunchAnimation() {
    releaseFlutterFrame()
    guard mascotSplashOverlay != nil || mascotSplashPlayer != nil || mascotSplashPosterHost != nil else { return }
    mascotSplashTimeout?.cancel()
    mascotSplashTimeout = nil
    mascotSplashStatusObservation?.invalidate()
    mascotSplashStatusObservation = nil
    if let observer = mascotSplashEndObserver {
      NotificationCenter.default.removeObserver(observer)
      mascotSplashEndObserver = nil
    }
    mascotSplashPlayer?.pause()
    mascotSplashOverlay?.removeFromSuperview()
    mascotSplashOverlay = nil
    mascotSplashPlayer = nil
    mascotSplashPosterHost?.removeFromSuperview()
    mascotSplashPosterHost = nil
    mascotSplashWindow?.isHidden = true
    mascotSplashWindow = nil
    window?.makeKeyAndVisible()
    mascotSplashItemReady = false
    mascotSplashPlaybackRequested = false
    mascotSplashPlaybackStarted = false
  }

  private var hasCalendarAccess: Bool {
    let status = EKEventStore.authorizationStatus(for: .event)
    if #available(iOS 17.0, *) { return status == .fullAccess }
    return status == .authorized
  }

  private func handleCalendarCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "calendarHasAccess" { result(hasCalendarAccess); return }
    guard hasCalendarAccess else {
      result(FlutterError(code: "calendar_permission", message: "Calendar access denied", details: nil)); return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "calendarList":
        calendarPermissionStore.reset()
        result(calendarPermissionStore.calendars(for: .event).map {
          ["id": $0.calendarIdentifier, "name": $0.title, "isReadOnly": !$0.allowsContentModifications, "accountType": $0.source.sourceType == .local ? "LOCAL" : "OTHER"] as [String: Any]
        })
      case "calendarCreate":
        guard let name = args["name"] as? String,
              let source = calendarPermissionStore.sources.first(where: { $0.sourceType == .local })
                ?? ((args["localOnly"] as? Bool == true) ? nil : calendarPermissionStore.defaultCalendarForNewEvents?.source) else {
          result(FlutterError(code: "calendar_source", message: "No writable calendar account", details: nil)); return
        }
        let calendar = EKCalendar(for: .event, eventStore: calendarPermissionStore)
        calendar.title = name
        calendar.source = source
        try calendarPermissionStore.saveCalendar(calendar, commit: true)
        result(calendar.calendarIdentifier)
      case "calendarEvents":
        calendarPermissionStore.reset()
        guard let id = args["calendarId"] as? String,
              let calendar = calendarPermissionStore.calendar(withIdentifier: id) else {
          result(FlutterError(code: "calendar_arguments", message: "Invalid calendar", details: nil)); return
        }
        let events: [EKEvent]
        if let ids = args["eventIds"] as? [String] {
          events = ids.compactMap { calendarPermissionStore.event(withIdentifier: $0) }
            .filter { $0.calendar.calendarIdentifier == id }
        } else if let from = args["from"] as? Double, let to = args["to"] as? Double {
          let predicate = calendarPermissionStore.predicateForEvents(
            withStart: Date(timeIntervalSince1970: from / 1000), end: Date(timeIntervalSince1970: to / 1000), calendars: [calendar])
          events = calendarPermissionStore.events(matching: predicate)
        } else {
          result(FlutterError(code: "calendar_arguments", message: "Invalid range", details: nil)); return
        }
        result(events.map { event -> [String: Any] in
          ["eventId": event.eventIdentifier ?? "", "calendarId": id,
           "eventTitle": event.title ?? "", "eventDescription": event.notes ?? "",
           "eventLocation": event.location ?? "",
           "eventStartDate": Int64(event.startDate.timeIntervalSince1970 * 1000),
           "eventEndDate": Int64(event.endDate.timeIntervalSince1970 * 1000),
           "eventStartTimeZone": "Asia/Shanghai", "eventEndTimeZone": "Asia/Shanghai",
           "reminders": (event.alarms ?? []).compactMap { alarm -> [String: Int]? in
             guard alarm.absoluteDate == nil, alarm.relativeOffset <= 0 else { return nil }
             return ["minutes": Int(-alarm.relativeOffset / 60)]
           }]
        })
      case "calendarDeleteEvent":
        guard let id = args["calendarId"] as? String,
              let eventId = args["eventId"] as? String,
              let expected = args["description"] as? String else {
          result(FlutterError(code: "calendar_arguments", message: "Invalid event", details: nil)); return
        }
        calendarPermissionStore.reset()
        if let event = calendarPermissionStore.event(withIdentifier: eventId) {
          guard event.calendar.calendarIdentifier == id, event.notes == expected else {
            result(FlutterError(code: "calendar_ownership", message: "Event ownership changed", details: nil)); return
          }
          try calendarPermissionStore.remove(event, span: .thisEvent, commit: true)
        }
        result(true)
      case "calendarSaveEvent":
        guard let id = args["calendarId"] as? String,
              let calendar = calendarPermissionStore.calendar(withIdentifier: id), calendar.allowsContentModifications,
              let start = args["start"] as? Double, let end = args["end"] as? Double, end > start else {
          result(FlutterError(code: "calendar_arguments", message: "Invalid event or calendar", details: nil)); return
        }
        let prior = (args["eventId"] as? String).flatMap { calendarPermissionStore.event(withIdentifier: $0) }
        // Never update an event moved by the user to an unrelated calendar.
        let event = prior?.calendar.calendarIdentifier == id ? prior! : EKEvent(eventStore: calendarPermissionStore)
        if let notes = args["description"] as? String,
           let marker = notes.components(separatedBy: "\n").last, marker.hasPrefix("[sanqian-reminder:"),
           let prior = prior {
          guard prior.calendar.calendarIdentifier == id,
                prior.notes?.components(separatedBy: "\n").last == marker else {
            result(FlutterError(code: "calendar_ownership", message: "Event ownership changed", details: nil)); return
          }
        }
        event.calendar = calendar
        event.title = args["title"] as? String
        event.location = args["location"] as? String
        event.notes = args["description"] as? String
        event.timeZone = TimeZone(identifier: "Asia/Shanghai")
        event.startDate = Date(timeIntervalSince1970: start / 1000)
        event.endDate = Date(timeIntervalSince1970: end / 1000)
        if let leads = args["reminders"] as? [Int] {
          event.alarms = leads.map { EKAlarm(relativeOffset: -Double($0) * 60) }
        }
        try calendarPermissionStore.save(event, span: .thisEvent, commit: true)
        result(event.eventIdentifier)
      default: result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "calendar_write", message: error.localizedDescription, details: nil))
    }
  }

  private func setupSystemTimeChangeObserver() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleSignificantTimeChange),
      name: UIApplication.significantTimeChangeNotification,
      object: nil
    )
  }

  @objc private func handleSignificantTimeChange() {
    guard #available(iOS 14.0, *) else { return }
    WidgetCenter.shared.reloadAllTimelines()
    print("🔄 [AppDelegate] Significant time change detected, widget timelines reloaded")
  }

  private func setupWidgetDataChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      print("Failed to get FlutterViewController")
      return
    }

    widgetDataChannel = FlutterMethodChannel(
      name: "com.wheretosleepinnju/widget_data",
      binaryMessenger: controller.binaryMessenger
    )

    widgetDataChannel?.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMethodCall(call, result: result)
    }
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if !widgetSharingEnabled && call.method != "getPlatformInfo" {
      result(false)
      return
    }
    switch call.method {
    case "sendWidgetData":
      handleSendWidgetData(call, result: result)
    case "sendLiveActivityData":
      handleSendLiveActivityData(call, result: result)
    case "sendUnifiedDataPackage":
      handleSendUnifiedDataPackage(call, result: result)
    case "refreshWidgets":
      handleRefreshWidgets(result: result)
    case "refreshLiveActivities":
      handleRefreshLiveActivities(result: result)
    case "getPlatformInfo":
      handleGetPlatformInfo(result: result)
    case "debugReadWidgetData":
      handleDebugReadWidgetData(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleSendWidgetData(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    print("📱 [AppDelegate] ========== Widget Data Request ==========")

    guard let args = call.arguments as? [String: Any] else {
      print("❌ [AppDelegate] Invalid arguments type")
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
      return
    }

    print("✅ [AppDelegate] Received arguments with keys: \(args.keys)")
    print("📊 [AppDelegate] Timestamp: \(args["timestamp"] ?? "N/A")")
    print("📊 [AppDelegate] Platform: \(args["platform"] ?? "N/A")")

    // Extract the actual widget data from the 'data' field
    guard let widgetData = args["data"] as? [String: Any] else {
      print("❌ [AppDelegate] Missing 'data' field in arguments")
      result(FlutterError(code: "INVALID_DATA", message: "Missing 'data' field", details: nil))
      return
    }

    print("✅ [AppDelegate] Widget data extracted successfully")
    print("📊 [AppDelegate] Widget data keys: \(widgetData.keys)")

    // Log key data fields
    if let todayCourses = widgetData["todayCourses"] as? [[String: Any]] {
      print("📚 [AppDelegate] Today's courses count: \(todayCourses.count)")
    }
    if let currentCourse = widgetData["currentCourse"] as? [String: Any],
       let courseName = currentCourse["name"] as? String {
      print("📖 [AppDelegate] Current course: \(courseName)")
    }
    if let nextCourse = widgetData["nextCourse"] as? [String: Any],
       let courseName = nextCourse["name"] as? String {
      print("📖 [AppDelegate] Next course: \(courseName)")
    }

    // Save to UserDefaults (App Group)
    print("🔐 [AppDelegate] Attempting to access App Group: \(kAppGroupIdentifier)")

    if let appGroup = UserDefaults(suiteName: kAppGroupIdentifier) {
      print("✅ [AppDelegate] App Group accessed successfully")

      do {
        let jsonData = try JSONSerialization.data(withJSONObject: widgetData, options: [])
        let dataSize = jsonData.count
        print("📦 [AppDelegate] JSON serialized successfully, size: \(dataSize) bytes")

        appGroup.set(jsonData, forKey: "widget_data")
        appGroup.set(Date(), forKey: "last_update_time")

        let syncSuccess = appGroup.synchronize()
        print("💾 [AppDelegate] UserDefaults synchronize: \(syncSuccess ? "✅ Success" : "⚠️ Failed")")

        // Verify data was saved
        if let savedData = appGroup.data(forKey: "widget_data") {
          print("✅ [AppDelegate] Data verified in UserDefaults: \(savedData.count) bytes")
        } else {
          print("⚠️ [AppDelegate] Warning: Could not verify saved data")
        }

        // Trigger widget refresh immediately
        if #available(iOS 14.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
          print("🔄 [AppDelegate] Widget refresh triggered via WidgetCenter")
        } else {
          print("⚠️ [AppDelegate] WidgetKit not available (iOS < 14)")
        }

        print("✅ [AppDelegate] ========== Widget Data Saved Successfully ==========")
        result(true)
      } catch {
        print("❌ [AppDelegate] JSON serialization failed: \(error)")
        print("❌ [AppDelegate] Error details: \(error.localizedDescription)")
        result(FlutterError(code: "SAVE_ERROR", message: error.localizedDescription, details: nil))
      }
    } else {
      print("❌ [AppDelegate] Failed to access App Group: \(kAppGroupIdentifier)")
      print("⚠️ [AppDelegate] Make sure App Groups capability is enabled")
      result(FlutterError(code: "APP_GROUP_ERROR", message: "Failed to access App Group", details: nil))
    }
  }

  private func handleSendLiveActivityData(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
      return
    }

    print("Received live activity data: \(args.keys)")

    // Extract the 'activities' array to match the structure expected by WidgetDataManager.loadLiveActivityData()
    // Flutter sends: {'activities': [...], 'timestamp': ..., 'platform': ...}
    // Swift Reader expects: [LiveActivityData] (Array)
    guard let activitiesData = args["activities"] else {
        print("❌ [AppDelegate] Missing 'activities' field in live activity data")
        result(FlutterError(code: "INVALID_DATA", message: "Missing 'activities' field", details: nil))
        return
    }

    // Save to UserDefaults (App Group)
    if let appGroup = UserDefaults(suiteName: kAppGroupIdentifier) {
      do {
        // We serialize the array directly
        let jsonData = try JSONSerialization.data(withJSONObject: activitiesData, options: [])
        appGroup.set(jsonData, forKey: "live_activity_data")
        appGroup.synchronize()
        print("Live activity data saved successfully")
        result(true)
      } catch {
        print("Failed to save live activity data: \(error)")
        result(FlutterError(code: "SAVE_ERROR", message: error.localizedDescription, details: nil))
      }
    } else {
      result(FlutterError(code: "APP_GROUP_ERROR", message: "Failed to access App Group", details: nil))
    }
  }

  private func handleSendUnifiedDataPackage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
      return
    }

    print("Received unified data package")

    // Save to UserDefaults (App Group)
    if let appGroup = UserDefaults(suiteName: kAppGroupIdentifier) {
      do {
        let jsonData = try JSONSerialization.data(withJSONObject: args, options: [])
        appGroup.set(jsonData, forKey: "unified_data_package")
        appGroup.set(Date(), forKey: "last_update_time")
        appGroup.synchronize()
        print("Unified data package saved successfully")
        result(true)
      } catch {
        print("Failed to save unified data package: \(error)")
        result(FlutterError(code: "SAVE_ERROR", message: error.localizedDescription, details: nil))
      }
    } else {
      result(FlutterError(code: "APP_GROUP_ERROR", message: "Failed to access App Group", details: nil))
    }
  }

  private func handleRefreshWidgets(result: @escaping FlutterResult) {
    // Trigger widget refresh
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
      print("Widget refresh triggered successfully")
      result(true)
    } else {
      result(FlutterError(code: "UNSUPPORTED", message: "Widgets require iOS 14+", details: nil))
    }
  }

  private func handleRefreshLiveActivities(result: @escaping FlutterResult) {
    // Trigger Live Activities refresh
    if #available(iOS 16.1, *) {
      print("Live Activities refresh requested (requires ActivityKit)")
      result(true)
    } else {
      result(FlutterError(code: "UNSUPPORTED", message: "Live Activities require iOS 16.1+", details: nil))
    }
  }

  private func handleGetPlatformInfo(result: @escaping FlutterResult) {
    let platformInfo: [String: Any] = [
      "platform": "ios",
      "version": UIDevice.current.systemVersion,
      "model": UIDevice.current.model,
      "supportsWidgets": widgetSharingEnabled,
      "supportsLiveActivities": widgetSharingEnabled,
      "appGroupId": widgetSharingEnabled ? kAppGroupIdentifier : ""
    ]
    result(platformInfo)
  }

  private func handleDebugReadWidgetData(result: @escaping FlutterResult) {
    print("🔍 [AppDelegate] ========== Debug: Reading Widget Data ==========")

    guard let appGroup = UserDefaults(suiteName: kAppGroupIdentifier) else {
      print("❌ [AppDelegate] Failed to access App Group")
      result(FlutterError(code: "APP_GROUP_ERROR", message: "Cannot access App Group", details: nil))
      return
    }

    print("✅ [AppDelegate] App Group accessed")

    // Check if data exists
    guard let jsonData = appGroup.data(forKey: "widget_data") else {
      print("❌ [AppDelegate] No data found in App Group")
      print("🔍 [AppDelegate] Available keys:")
      for (key, _) in appGroup.dictionaryRepresentation() {
        print("   - \(key)")
      }
      result(FlutterError(code: "NO_DATA", message: "No widget_data found", details: nil))
      return
    }

    print("✅ [AppDelegate] Data found: \(jsonData.count) bytes")

    // Try to parse and return the data
    do {
      let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
      if let dict = jsonObject as? [String: Any] {
        print("✅ [AppDelegate] Data parsed successfully")
        print("📊 [AppDelegate] Keys: \(dict.keys)")

        if let todayCourses = dict["todayCourses"] as? [[String: Any]] {
          print("📚 [AppDelegate] Today's courses: \(todayCourses.count)")
        }

        result(dict)
      } else {
        print("❌ [AppDelegate] Data is not a dictionary")
        result(FlutterError(code: "INVALID_FORMAT", message: "Data is not a dictionary", details: nil))
      }
    } catch {
      print("❌ [AppDelegate] Failed to parse JSON: \(error)")
      result(FlutterError(code: "PARSE_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  // Handle Deep Links (URL Scheme)
  override func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    print("🔗 [AppDelegate] Received URL: \(url.absoluteString)")

    // Handle ncs:// scheme
    if url.scheme == "ncs" {
      handleDeepLink(url)
      return true
    }


    return super.application(application, open: url, options: options)
  }

  private func handleDeepLink(_ url: URL) {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      print("❌ [AppDelegate] Invalid URL components")
      return
    }

    let path = components.host ?? ""
    print("🔗 [AppDelegate] Deep link path: \(path)")

    switch path {
    case "arrived":
      handleArrivedDeepLink(url: url)
    case "course":
      handleCourseDeepLink(url: url)
    default:
      print("⚠️ [AppDelegate] Unknown deep link path: \(path)")
    }
  }

  /// 处理"我已到达"按钮点击
  /// URL format: ncs://arrived/{courseId}
  private func handleArrivedDeepLink(url: URL) {
    let pathComponents = url.pathComponents.filter { $0 != "/" }
    guard let courseId = pathComponents.first else {
      print("❌ [AppDelegate] No course ID in arrived deep link")
      return
    }

    print("✅ [AppDelegate] User arrived for course: \(courseId)")
    
    // 记录已到达的课程
    let defaults = UserDefaults(suiteName: kAppGroupIdentifier)
    defaults?.set(courseId, forKey: "arrivedCourseId")
    defaults?.set(Date(), forKey: "arrivedCourseTime")
    defaults?.synchronize()

    // Close Live Activity
    if #available(iOS 16.1, *) {
      endLiveActivityForCourse(courseId: courseId)
    }

    // Refresh widgets to update status
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
      print("🔄 [AppDelegate] Widgets refreshed after arrived action")
    }
  }

  /// 结束指定课程的 Live Activity
  @available(iOS 16.1, *)
  private func endLiveActivityForCourse(courseId: String) {
    // 由于 CourseActivityAttributes 在 ScheduleWidget target 中，
    // 我们通过 UserDefaults 通知 Widget 关闭 Live Activity
    let defaults = UserDefaults(suiteName: kAppGroupIdentifier)
    defaults?.set(courseId, forKey: "liveActivityEndRequest")
    defaults?.set(Date(), forKey: "liveActivityEndRequestTime")
    defaults?.synchronize()

    print("🛑 [AppDelegate] Requested to end Live Activity for course: \(courseId)")
  }

  /// 处理课程详情链接（预留）
  /// URL format: ncs://course/{courseId}
  private func handleCourseDeepLink(url: URL) {
    let pathComponents = url.pathComponents.filter { $0 != "/" }
    guard let courseId = pathComponents.first else {
      print("❌ [AppDelegate] No course ID in course deep link")
      return
    }

    print("ℹ️ [AppDelegate] Course detail request: \(courseId)")
    // 可以在这里打开课程详情页面（如果需要的话）
  }

}
