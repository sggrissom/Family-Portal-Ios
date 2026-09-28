import SwiftUI
import SwiftData

/// The Growth tab. Until the family chart lands (phase 4) it lists who has been measured and opens each person's own chart.
struct GrowthRootView: View {
    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]
    @Environment(AuthService.self) private var authService

    private var measured: [Person] {
        FamilyGroups.chipOrder(
            people: people,
            relations: relations.map(\.edge),
            ownFamilyId: authService.currentUser?.familyId
        )
        .filter { !$0.growthData.isEmpty }
    }

    var body: some View {
        List {
            if measured.isEmpty {
                ContentUnavailableView(Copy.growthPage.noData, systemImage: "chart.line.uptrend.xyaxis")
            } else {
                ForEach(measured) { person in
                    NavigationLink {
                        MeasurementListView(personId: person.id)
                    } label: {
                        PersonRowView(person: person)
                    }
                }
            }
        }
        .navigationTitle(Copy.growthPage.title)
    }
}
