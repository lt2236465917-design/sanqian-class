import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: ScheduleEntry
    var body: some View { PersonalWidgetView(entry: entry.desktopPresentation) }
}
