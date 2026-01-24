import SwiftUI
import SwiftData
import Charts

struct MeasurementListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var people: [Person]
    private var person: Person? { people.first }

    @State private var selectedType: MeasurementType = .height
    @State private var showingAddMeasurement = false

    private let personId: UUID

    private var filteredMeasurements: [GrowthData] {
        guard let person else { return [] }
        return person.growthData
            .filter { $0.measurementType == selectedType }
            .sorted { $0.date > $1.date }
    }

    init(personId: UUID) {
        self.personId = personId
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Measurement Type", selection: $selectedType) {
                ForEach(MeasurementType.allCases, id: \.self) { type in
                    Text(type.rawValue.capitalized)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if filteredMeasurements.count >= 2 {
                GrowthChartView(
                    measurements: filteredMeasurements,
                    measurementType: selectedType
                )
            }

            if filteredMeasurements.isEmpty {
                ContentUnavailableView(
                    "No \(selectedType.rawValue.capitalized) Measurements",
                    systemImage: "ruler",
                    description: Text("Tap the + button to add a measurement.")
                )
            } else {
                List {
                    ForEach(filteredMeasurements, id: \.id) { measurement in
                        MeasurementRowView(value: measurement.value, unit: measurement.unit, date: measurement.date)
                    }
                    .onDelete(perform: deleteMeasurements)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddMeasurement = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddMeasurement) {
            AddMeasurementView(personId: personId, initialType: selectedType)
        }
    }

    private func deleteMeasurements(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredMeasurements[index])
        }
    }
}
