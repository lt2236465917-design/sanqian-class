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
        guard let zone = TimeZone(identifier: "Asia/Shanghai") else {
            completion(Timeline(entries: [current], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            completion(Timeline(entries: [current], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
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
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PersonalWidgetEntry

    private var accent: Color {
        if renderingMode != .fullColor { return .primary }
        return colorScheme == .dark ? Color(red: 0.886, green: 0.812, blue: 0.949)
            : Color(red: 0.408, green: 0.302, blue: 0.482)
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }
    private var events: [PersonalWidgetEvent] {
        entry.sourceState == .ready ? entry.events.sorted { $0.start < $1.start } : []
    }
    private var today: [PersonalWidgetEvent] {
        events.filter { calendar.isDate($0.start, inSameDayAs: entry.date) || active($0) }
    }
    private var remaining: [PersonalWidgetEvent] { today.filter { $0.end > entry.date } }
    private var primary: PersonalWidgetEvent? { events.first { $0.end > entry.date } }
    private var following: [PersonalWidgetEvent] {
        guard let primary else { return [] }
        return events.filter { $0.end > entry.date && $0.id != primary.id && calendar.isDate($0.start, inSameDayAs: primary.start) }
    }
    private func active(_ event: PersonalWidgetEvent) -> Bool { event.start <= entry.date && event.end > entry.date }
    private var dateText: String {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: entry.date)
        return "\(parts.month ?? 1)/\(parts.day ?? 1) 周\(["日", "一", "二", "三", "四", "五", "六"][(parts.weekday ?? 1) - 1])"
    }
    private func dateLabel(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: entry.date) { return "今天" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: entry.date), calendar.isDate(date, inSameDayAs: tomorrow) { return "明天" }
        return "\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日"
    }
    private var summary: String {
        if entry.sourceState != .ready { return "" }
        if !remaining.isEmpty { return "今日还有 \(remaining.count) 节" }
        return today.isEmpty ? "今天没有课" : "今日已结束"
    }
    private var emptyTitle: String {
        switch entry.sourceState {
        case .notSynced: return "课表尚未同步"
        case .unavailable: return "课表暂时无法读取"
        case .ready: return events.isEmpty ? "暂无已排课程" : summary
        }
    }
    private var emptyHint: String {
        switch entry.sourceState {
        case .notSynced: return "打开 App 导入或选择课表"
        case .unavailable: return "打开 App 重新同步课表"
        case .ready: return "后续安排会显示在这里"
        }
    }
    private func clock(_ date: Date) -> String {
        String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
    private func room(_ event: PersonalWidgetEvent) -> String {
        event.classroom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "地点待定" : event.classroom
    }
    private func status(_ event: PersonalWidgetEvent) -> String {
        active(event) ? "上课中" : calendar.isDate(event.start, inSameDayAs: entry.date) ? "下一节" : "\(dateLabel(event.start)) · 下次上课"
    }
    private func url(_ event: PersonalWidgetEvent? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "ncs"
        components.host = "schedule"
        let target = event?.start ?? entry.date
        components.queryItems = [URLQueryItem(name: "date", value: String(Int(target.timeIntervalSince1970 * 1000)))]
        if let event { components.queryItems?.append(URLQueryItem(name: "occurrence", value: event.id)) }
        return components.url!
    }
    private var header: some View {
        Link(destination: url()) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateText).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                if family != .systemSmall && primary != nil {
                    Text(summary).font(.system(size: 12)).lineLimit(1)
                }
            }.foregroundStyle(.secondary)
        }.buttonStyle(.plain)
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 14) {
                header
                if let primary {
                    if family == .systemLarge && !remaining.isEmpty {
                        timeline(height: geometry.size.height)
                    } else if family == .systemSmall {
                        hero(primary, compact: true, roomLines: geometry.size.height >= 150 ? 2 : 1)
                    } else {
                        overview(primary, width: geometry.size.width, height: geometry.size.height)
                    }
                } else {
                    emptyContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .widgetURL(url(family == .systemSmall ? primary : nil))
        .environment(\.timeZone, calendar.timeZone)
        .containerBackground(colorScheme == .dark
            ? Color(red: 0.129, green: 0.114, blue: 0.145)
            : Color(red: 0.969, green: 0.961, blue: 0.949), for: .widget)
    }
    private func hero(_ event: PersonalWidgetEvent, compact: Bool, roomLines: Int = 2) -> some View {
        Link(destination: url(event)) {
            VStack(alignment: .leading, spacing: compact ? 4 : 7) {
                Text(status(event)).font(.system(size: 12, weight: .medium)).foregroundStyle(accent).lineLimit(1)
                    .widgetAccentable()
                Text(event.title).font(.system(size: compact ? 18 : 20, weight: .semibold))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Text(event.clockRange.isEmpty ? "\(clock(event.start))–\(clock(event.end))" : event.clockRange).font(.system(size: 16, weight: .medium)).monospacedDigit()
                    .lineLimit(1)
                Text(room(event)).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(roomLines).truncationMode(.tail)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func overview(_ primary: PersonalWidgetEvent, width: CGFloat, height: CGFloat) -> some View {
        return HStack(alignment: .top, spacing: 16) {
            hero(primary, compact: width < 290 || height < 170, roomLines: height < 150 ? 1 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !following.isEmpty && width >= 270 {
                Rectangle().fill(.primary.opacity(0.08)).frame(width: 1)
                ViewThatFits(in: .vertical) {
                    ForEach(Array((1...min(2, following.count)).reversed()), id: \.self) { count in
                        upcoming(count: count)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: max(100, (width - 33) * 0.38))
                .frame(maxHeight: .infinity)
            }
        }
    }
    private func upcoming(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("接下来").font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach(Array(following.prefix(count))) { event in
                Link(destination: url(event)) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clock(event.start)).font(.system(size: 12, weight: .medium))
                            .monospacedDigit().foregroundStyle(.secondary)
                        Text(event.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
            if following.count > count {
                Text("另有 \(following.count - count) 节").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private func timeline(height: CGFloat) -> some View {
        // Let SwiftUI measure the actual wrapped titles and footer instead of
        // reserving the maximum two-line height for every course.
        let maximum = max(1, min(today.count, Int(height / 44)))
        return ViewThatFits(in: .vertical) {
            ForEach(Array((1...maximum).reversed()), id: \.self) { capacity in
                timelineRows(capacity: capacity)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxHeight: .infinity, alignment: .top)
    }
    private func timelineRows(capacity: Int) -> some View {
        let focus = today.firstIndex { $0.end > entry.date } ?? 0
        let context = capacity > 1 ? 1 : 0
        let start = max(0, min(focus - context, today.count - capacity))
        let visible = Array(today.dropFirst(start).prefix(capacity))
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(visible) { event in
                Link(destination: url(event)) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(clock(event.start)).font(.system(size: 14, weight: .medium))
                            Text(clock(event.end)).font(.system(size: 12)).foregroundStyle(.secondary)
                        }.monospacedDigit().frame(width: 48, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                            Text(room(event)).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        if active(event) {
                            Text("上课中").font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
                        }
                    }
                    .padding(10)
                    .background(active(event) ? accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 14))
                    .opacity(event.end <= entry.date ? 0.55 : 1)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if today.count > visible.count {
                Text("共 \(today.count) 节 · 点开查看完整日程").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 0)
            Text(emptyTitle).font(.system(size: 20, weight: .semibold)).lineLimit(2)
            Text(emptyHint).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
        }
    }
}

struct PersonalScheduleWidget: Widget {
    let kind = "SanqianPersonalSchedule"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PersonalWidgetProvider()) { PersonalWidgetView(entry: $0) }
            .configurationDisplayName("三千上课")
            .description("正在上课、下一节和今日剩余课程")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// Keeps existing preview fixtures useful without maintaining a second desktop UI.
extension ScheduleEntry {
    var desktopPresentation: PersonalWidgetEntry {
        if let personalEntry { return personalEntry }
        guard errorMessage == nil, let data = widgetData else {
            return PersonalWidgetEntry(date: date, events: [], sourceState: errorMessage == nil ? .notSynced : .unavailable)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let base = calendar.startOfDay(for: date)
        let events = [(0, data.todayCourses), (1, data.tomorrowCourses)].flatMap { offset, courses in
            courses.compactMap { course -> PersonalWidgetEvent? in
                guard let range = data.timeTemplate.getPeriodRange(startPeriod: course.startPeriod, periodCount: course.periodCount),
                      let day = calendar.date(byAdding: .day, value: offset, to: base) else { return nil }
                func clock(_ value: String) -> Date? {
                    let parts = value.split(separator: ":").compactMap { Int($0) }
                    guard parts.count == 2 else { return nil }
                    return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)
                }
                guard let start = clock(range.startTime), let end = clock(range.endTime), end > start else { return nil }
                return PersonalWidgetEvent(id: "preview-\(offset)-\(course.id)", title: course.name,
                    classroom: course.classroom ?? "", startMs: start.timeIntervalSince1970 * 1000,
                    endMs: end.timeIntervalSince1970 * 1000, clockRange: "\(range.startTime)–\(range.endTime)")
            }
        }
        return PersonalWidgetEntry(date: date, events: events)
    }
}
