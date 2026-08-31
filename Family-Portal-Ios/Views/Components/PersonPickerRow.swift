import SwiftUI

/// The "For" row an add sheet opens with. Its own view so the milestone and measurement sheets cannot word or order the roster differently, and so a sheet opened without a person has one place to ask.
struct PersonPickerRow: View {
    let people: [Person]
    @Binding var selection: UUID?

    var body: some View {
        Picker("For", selection: $selection) {
            // Only offered while nothing is chosen: once somebody is, there is nothing to go back to — an add sheet with no person cannot save.
            if selection == nil {
                Text("Choose someone").tag(UUID?.none)
            }
            ForEach(people, id: \.id) { person in
                Text(person.name).tag(UUID?.some(person.id))
            }
        }
    }
}
