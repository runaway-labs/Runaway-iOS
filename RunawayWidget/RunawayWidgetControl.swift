import AppIntents
import SwiftUI
import WidgetKit

struct RunawayWidgetControl: ControlWidget {
    static let kind = "com.jackrudelic.labs.Runaway-iOS.TodayControl"
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ReviewTodayIntent()) {
                Label("Review Today", systemImage: "point.forward.to.point.capsulepath")
            }
        }
        .displayName("Review Today's Path")
        .description("Open Runaway's adaptive training decision for today.")
    }
}
