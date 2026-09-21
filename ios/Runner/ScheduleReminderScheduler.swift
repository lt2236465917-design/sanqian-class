import Foundation
import UserNotifications

/// Migration only. Dated events and alarms are now owned by the system calendar.
final class ScheduleReminderScheduler {
    static let shared = ScheduleReminderScheduler()
    func clearLegacy(completion: @escaping () -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests
                .filter { $0.identifier.hasPrefix("sanqian.schedule.") }.map { $0.identifier })
            DispatchQueue.main.async { completion() }
        }
    }
}
