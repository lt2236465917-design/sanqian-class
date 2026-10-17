import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: ScheduleEntry
    var body: some View { PersonalWidgetView(entry: entry.desktopPresentation) }
}
