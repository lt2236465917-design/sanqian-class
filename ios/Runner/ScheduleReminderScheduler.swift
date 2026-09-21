import Foundation
import UserNotifications

/// App-owned budget, not a claim about an OS fixed limit. All input timestamps
/// are absolute instants derived from Asia/Shanghai schedule dates.
final class ScheduleReminderScheduler {
    static let shared = ScheduleReminderScheduler()
    private let center = UNUserNotificationCenter.current()
    private let queue = DispatchQueue(label: "sanqian.reminders")
    private var generation = 0
    private let prefix = "sanqian.schedule."

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        center.requestAuthorization(options: [.alert, .sound], completionHandler: completion)
    }

    func replace(occurrences: [[String: Any]], leadMinutes: [Int], completion: @escaping ([String: Any]) -> Void) {
        queue.async {
            self.generation += 1
            let generation = self.generation
            self.center.getNotificationSettings { settings in
                self.center.getPendingNotificationRequests { pending in
                    self.queue.async {
                        guard generation == self.generation else { completion(["superseded": true]); return }
                        let own = pending.filter { $0.identifier.hasPrefix(self.prefix) }
                        self.center.removePendingNotificationRequests(withIdentifiers: own.map(\.identifier))
                        let permitted = [.authorized, .provisional].contains(settings.authorizationStatus)
                        guard permitted else { completion(["count": 0, "permission": "denied"]); return }
                        var candidates: [(String, Date, UNMutableNotificationContent)] = []
                        for row in occurrences {
                            guard let id = row["id"] as? String, let start = row["startMs"] as? Double,
                                  let end = row["endMs"] as? Double, end > start,
                                  let title = row["title"] as? String else { continue }
                            for lead in Set(leadMinutes).intersection([15, 180, 1440]) {
                                let fire = Date(timeIntervalSince1970: start / 1000 - Double(lead * 60))
                                guard fire > Date() else { continue }
                                let content = UNMutableNotificationContent()
                                content.title = title
                                let label = lead == 15 ? "15 分钟" : lead == 180 ? "3 小时" : "1 天"
                                content.body = "还有\(label)上课 · \(row["classroom"] as? String ?? "")"
                                content.sound = .default
                                candidates.append(("\(self.prefix)\(id).\(lead)", fire, content))
                            }
                        }
                        candidates.sort { $0.1 < $1.1 }
                        let capacity = max(0, 60 - (pending.count - own.count))
                        let selected = Array(candidates.prefix(capacity))
                        let group = DispatchGroup()
                        let lock = NSLock()
                        var failures = 0
                        for (id, fire, content) in selected {
                            var calendar = Calendar(identifier: .gregorian)
                            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
                            var date = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                            date.timeZone = calendar.timeZone
                            group.enter()
                            self.center.add(UNNotificationRequest(identifier: id, content: content,
                                trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false))) { error in
                                lock.lock(); if error != nil { failures += 1 }; lock.unlock(); group.leave()
                            }
                        }
                        group.notify(queue: self.queue) {
                            completion(["count": selected.count - failures, "failed": failures,
                                "permission": "authorized", "limited": candidates.count > selected.count,
                                "coverageEndMs": selected.last.map { $0.1.timeIntervalSince1970 * 1000 } ?? 0])
                        }
                    }
                }
            }
        }
    }
}
