import WidgetKit
import SwiftUI

struct PersonalWidgetEvent: Decodable, Identifiable {
    let id: String
    let title: String
    let classroom: String
    let startMs: Double
    let endMs: Double
    let clockRange: String
    var start: Date { Date(timeIntervalSince1970: startMs / 1000) }
    var end: Date { Date(timeIntervalSince1970: endMs / 1000) }
}
struct PersonalWidgetSnapshot: Decodable {
    let schemaVersion: Int
    let tableId: Int
    let revision: String
    let occurrences: [PersonalWidgetEvent]
}
struct PersonalWidgetEntry: TimelineEntry {
    let date: Date
    let events: [PersonalWidgetEvent]
    var sourceState: PersonalWidgetSourceState = .ready
}
enum PersonalWidgetSourceState {
    case ready, notSynced, unavailable
}
struct PersonalWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> PersonalWidgetEntry { PersonalWidgetEntry(date: Date(), events: []) }
    func getSnapshot(in context: Context, completion: @escaping (PersonalWidgetEntry) -> Void) {
        completion(readEntry(at: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PersonalWidgetEntry>) -> Void) {
        let now = Date()
        let current = readEntry(at: now)
        let events = current.events
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let boundaries = Set(events.flatMap { [$0.start, $0.end] }.filter { $0 > now && $0 < tomorrow })
        let dates = [now] + boundaries.sorted() + [tomorrow]
        let policy: TimelineReloadPolicy = current.sourceState == .ready
            ? .atEnd : .after(now.addingTimeInterval(15 * 60))
        completion(Timeline(entries: dates.map {
            PersonalWidgetEntry(date: $0, events: events, sourceState: current.sourceState)
        }, policy: policy))
    }
    private func readEntry(at date: Date) -> PersonalWidgetEntry {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "ScheduleAppGroup") as? String,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            return PersonalWidgetEntry(date: date, events: [], sourceState: .unavailable)
        }
        let file = directory.appendingPathComponent("personal-schedule.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            return PersonalWidgetEntry(date: date, events: [], sourceState: .notSynced)
        }
        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(PersonalWidgetSnapshot.self, from: data),
              snapshot.schemaVersion == 1 else {
            return PersonalWidgetEntry(date: date, events: [], sourceState: .unavailable)
        }
        return PersonalWidgetEntry(date: date, events: snapshot.occurrences
            .filter { $0.end > $0.start }.sorted { $0.start < $1.start })
    }
}
struct PersonalWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: PersonalWidgetEntry
    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.886, green: 0.812, blue: 0.949)
            : Color(red: 0.408, green: 0.302, blue: 0.482)
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    private var today: [PersonalWidgetEvent] {
        entry.events.filter { calendar.isDate($0.start, inSameDayAs: entry.date) }
    }
    private var remaining: [PersonalWidgetEvent] {
        today.filter { $0.end > entry.date }
    }
    private var next: PersonalWidgetEvent? {
        entry.events.first { $0.end > entry.date }
    }
    private func dateLabel(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: entry.date) { return "今天" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: entry.date),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "明天" }
        let components = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekday = ["日", "一", "二", "三", "四", "五", "六"][(components.weekday ?? 1) - 1]
        return "\(components.month ?? 1)月\(components.day ?? 1)日 周\(weekday)"
    }
    private var emptyTitle: String {
        switch entry.sourceState {
        case .notSynced: return "课表尚未同步"
        case .unavailable: return "课表暂时无法读取"
        case .ready:
            if entry.events.isEmpty { return "暂无已排课程" }
            return today.isEmpty ? "今天没有课" : "今日课程已结束"
        }
    }
    private var emptyHint: String {
        switch entry.sourceState {
        case .notSynced: return "打开 App 导入或选择课表"
        case .unavailable: return "打开 App 重新同步课表"
        case .ready:
            return entry.events.isEmpty ? "已确认时间的课程会显示在这里" : "暂无后续课程，可在 App 中更新"
        }
    }
    private func room(_ event: PersonalWidgetEvent) -> String {
        event.classroom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "地点待定" : event.classroom
    }
    private func badge(_ text: String, active: Bool = false) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(accent.opacity(active ? 0.18 : 0.09), in: Capsule())
            .lineLimit(1)
    }
    private var header: some View {
        HStack(spacing: 4) {
            Text("三千上课").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
            Spacer(minLength: 2)
            if family == .systemSmall, let event = next, entry.sourceState == .ready {
                badge(event.start <= entry.date ? "上课中" : "下一节", active: event.start <= entry.date)
            } else if !remaining.isEmpty {
                Text("今日剩余 \(remaining.count) 节").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text(entry.date, format: .dateTime.month(.twoDigits).day(.twoDigits))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 10) {
            header
            if family == .systemSmall {
                smallContent
            } else if remaining.isEmpty {
                emptyContent
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(remaining.prefix(3))) { event in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accent.opacity(event.start <= entry.date ? 1 : 0.25))
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text(room(event)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(event.clockRange).font(.system(size: 11, weight: .medium)).monospacedDigit()
                                if event.start <= entry.date {
                                    Text("正在上课").font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                                }
                            }.fixedSize(horizontal: true, vertical: false)
                        }.frame(maxHeight: .infinity)
                    }
                }
                if remaining.count > 3 {
                    Text("还有 \(remaining.count - 3) 节，打开 App 查看")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.timeZone, calendar.timeZone)
        .containerBackground(colorScheme == .dark
            ? Color(red: 0.129, green: 0.114, blue: 0.145)
            : Color(red: 0.969, green: 0.961, blue: 0.949), for: .widget)
    }
    @ViewBuilder private var smallContent: some View {
        if let event = next, entry.sourceState == .ready {
            Spacer(minLength: 0)
            Text(event.title).font(.system(size: 16, weight: .bold))
                .lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
            Text(event.clockRange).font(.system(size: 18, weight: .semibold))
                .monospacedDigit().foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.8)
            Text(dateLabel(event.start)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Label(room(event), systemImage: "mappin").font(.system(size: 11))
                .lineLimit(1).truncationMode(.middle)
        } else {
            Spacer(minLength: 0)
            Text(emptyTitle).font(.system(size: 16, weight: .semibold)).lineLimit(2)
            Text(emptyHint).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
        }
    }
    private var emptyContent: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: entry.sourceState == .ready ? "checkmark.circle" : "calendar.badge.exclamationmark")
                    .font(.system(size: 23, weight: .light)).foregroundStyle(accent)
                Text(emptyTitle).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                if next == nil {
                    Text(emptyHint).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let event = next, entry.sourceState == .ready {
                VStack(alignment: .leading, spacing: 5) {
                    Text("下次上课").font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                    Text(event.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text(dateLabel(event.start)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    Text(event.clockRange).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    Text(room(event)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }.frame(maxHeight: .infinity)
    }
}
struct PersonalScheduleWidget: Widget {
    let kind = "SanqianPersonalSchedule"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PersonalWidgetProvider()) { PersonalWidgetView(entry: $0) }
            .configurationDisplayName("三千上课")
            .description("正在上课、下一节和今日剩余课程")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
