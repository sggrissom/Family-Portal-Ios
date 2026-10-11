import SwiftUI
import WidgetKit

/// The widgets read only what the app publishes into the App Group (`WidgetStore`). See `plan.md`.
@main
struct FamilyRecordWidgetsBundle: WidgetBundle {
    var body: some Widget {
        OnThisDayWidget()
        MemoryWidget()
        QuoteWidget()
        FamilyAgesWidget()
    }
}
