import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: ScheduleEntry
    var body: some View { PersonalWidgetView(entry: entry.desktopPresentation) }
}
