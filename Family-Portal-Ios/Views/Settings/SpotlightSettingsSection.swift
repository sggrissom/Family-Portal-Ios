import SwiftData
import SwiftUI

/// Settings' **Search**: whether the family's people, moments and quotes show in system search. On by default; off removes everything already indexed, since anyone holding the unlocked phone can see it there.
struct SpotlightSettingsSection: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.modelContext) private var modelContext

    @AppStorage(SpotlightIndexer.enabledKey) private var isEnabled = true

    var body: some View {
        Section {
            Toggle(Copy.spotlight.toggle, isOn: $isEnabled)
        } header: {
            Text(Copy.spotlight.header)
        } footer: {
            Text(Copy.spotlight.footer)
        }
        .onChange(of: isEnabled) { _, enabled in
            Task {
                if enabled {
                    await SpotlightIndexer.shared.reindex(context: modelContext, domain: SpotlightIndexer.domain(for: authService.currentUser))
                } else {
                    await SpotlightIndexer.shared.removeAll()
                }
            }
        }
    }
}
