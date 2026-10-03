import WidgetKit
import SwiftUI

@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget {
        PersonalScheduleWidget()
        ScheduleWidget()
        if #available(iOS 16.1, *) {
            CourseActivityWidget()
        }
    }
}
