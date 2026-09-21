import Flutter
import UIKit

/// Uses the system iOS 26 tab bar without replacing its glass appearance or
/// selection indicator. UIKit supplies the interactive, refracting lens.
final class ScheduleTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    ScheduleTabBarView(
      frame: frame, id: viewId, messenger: messenger,
      configuration: args as? [String: Any] ?? [:]
    )
  }
}

private final class ScheduleTabAccessibilityElement: UIAccessibilityElement {
  weak var host: ScheduleTabBarHost?
  let index: Int

  init(host: ScheduleTabBarHost, index: Int, title: String) {
    self.host = host
    self.index = index
    super.init(accessibilityContainer: host)
    accessibilityLabel = title
    accessibilityIdentifier = "schedule-tab-\(index)"
    accessibilityTraits = .button
  }

  override func accessibilityActivate() -> Bool {
    host?.activateTab(index) ?? false
  }
}

private final class ScheduleTabBarHost: UIView {
  let tabBar = UITabBar()
  private var accessibleTabs: [ScheduleTabAccessibilityElement] = []
  var onAccessibilitySelect: ((Int) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    clipsToBounds = false
    tabBar.isTranslucent = true
    tabBar.itemPositioning = .fill
    addSubview(tabBar)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let height = tabBar.sizeThatFits(bounds.size).height
    tabBar.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
    let count = CGFloat(max(accessibleTabs.count, 1))
    let targetWidth = max(0, min(bounds.width - 32, count * 96))
    let targetLeft = (bounds.width - targetWidth) / 2
    for (index, element) in accessibleTabs.enumerated() {
      // Keep targets within the floating bar, stable as its lens moves.
      element.accessibilityFrameInContainerSpace = CGRect(
        x: targetLeft + CGFloat(index) * targetWidth / count,
        y: max(0, bounds.height - safeAreaInsets.bottom - 64),
        width: targetWidth / count, height: 64
      )
    }
  }

  func configureAccessibility(titles: [String]) {
    isAccessibilityElement = false
    tabBar.accessibilityElementsHidden = true
    accessibleTabs = titles.enumerated().map {
      ScheduleTabAccessibilityElement(host: self, index: $0.offset, title: $0.element)
    }
    accessibilityElements = accessibleTabs
    setNeedsLayout()
  }

  func updateAccessibility(selectedIndex: Int) {
    for (index, element) in accessibleTabs.enumerated() {
      element.accessibilityTraits = index == selectedIndex ? [.button, .selected] : .button
    }
  }

  func activateTab(_ index: Int) -> Bool {
    guard let items = tabBar.items, items.indices.contains(index) else { return false }
    tabBar.selectedItem = items[index]
    updateAccessibility(selectedIndex: index)
    onAccessibilitySelect?(index)
    return true
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }
}

private final class ScheduleTabBarView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let host: ScheduleTabBarHost
  private let channel: FlutterMethodChannel

  init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger, configuration: [String: Any]) {
    host = ScheduleTabBarHost(frame: frame)
    channel = FlutterMethodChannel(name: "chaoxi/schedule_navigation/\(id)", binaryMessenger: messenger)
    super.init()

    let items = [("日课表", "sun.max.fill"), ("周课表", "square.grid.3x3.fill"), ("月课表", "calendar")]
    host.tabBar.items = items.enumerated().map { index, item in
      let tab = UITabBarItem(title: item.0, image: UIImage(systemName: item.1), tag: index)
      tab.accessibilityIdentifier = "schedule-tab-\(index)"
      tab.accessibilityLabel = item.0
      return tab
    }
    host.tabBar.delegate = self
    // Keep the accessibility elements native too, so no Flutter overlay sits
    // above the system's interactive glass surface.
    host.configureAccessibility(titles: items.map { $0.0 })
    host.onAccessibilitySelect = { [weak self] index in
      self?.channel.invokeMethod("select", arguments: index)
    }
    update(configuration)

    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "update", let args = call.arguments as? [String: Any] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.update(args)
      result(nil)
    }
  }

  deinit { channel.setMethodCallHandler(nil) }

  func view() -> UIView { host }

  private func update(_ configuration: [String: Any]) {
    host.overrideUserInterfaceStyle = (configuration["dark"] as? Bool == true) ? .dark : .light
    if let argb = configuration["tint"] as? NSNumber {
      let value = argb.uint32Value
      host.tabBar.tintColor = UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: CGFloat((value >> 24) & 0xFF) / 255
      )
    }
    host.tabBar.unselectedItemTintColor = .label
    if let index = configuration["selectedIndex"] as? Int,
       let items = host.tabBar.items, items.indices.contains(index) {
      if host.tabBar.selectedItem !== items[index] {
        host.tabBar.selectedItem = items[index]
      }
      host.updateAccessibility(selectedIndex: index)
    }
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    host.updateAccessibility(selectedIndex: item.tag)
    channel.invokeMethod("select", arguments: item.tag)
  }
}
