import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action Button controls. Each runs an intent that opens the app (`Shared/FamilyRecordIntents.swift`), so the system performs it in the app, where the router is; the extension only draws the button.
struct AddQuoteControl: ControlWidget {
    static let kind = "com.familyrecord.ios.control.add-quote"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenAddQuoteIntent()) {
                Label(WidgetCopy.addQuoteControl, systemImage: "quote.bubble")
            }
        }
        .displayName("\(WidgetCopy.addQuoteControl)")
        .description("\(WidgetCopy.addQuoteControlDescription)")
    }
}

struct AddPhotosControl: ControlWidget {
    static let kind = "com.familyrecord.ios.control.add-photos"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: AddPhotosIntent()) {
                Label(WidgetCopy.addPhotosControl, systemImage: "photo.on.rectangle")
            }
        }
        .displayName("\(WidgetCopy.addPhotosControl)")
        .description("\(WidgetCopy.addPhotosControlDescription)")
    }
}
