import UIKit
import Flutter
import WidgetKit
import ActivityKit
import EventKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var widgetDataChannel: FlutterMethodChannel?
  private var scheduleNavigationChannel: FlutterMethodChannel?
  private var settingsChannel: FlutterMethodChannel?
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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
