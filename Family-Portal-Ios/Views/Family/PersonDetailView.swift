import SwiftUI
import SwiftData

struct PersonDetailView: View {
    @Query private var people: [Person]

    private var person: Person? { people.first }

    init(personId: UUID) {
        _people = Query(filter: #Predicate<Person> { person in
            person.id == personId
        })
    }

    private var age: String? {
        guard let birthday = person?.birthday else { return nil }
        let components = Calendar.current.dateComponents([.year, .month], from: birthday, to: Date())
        let years = components.year ?? 0
        let months = components.month ?? 0
        if years > 0 {
            return "\(years) year\(years == 1 ? "" : "s")"
        } else {
            return "\(months) month\(months == 1 ? "" : "s")"
        }
    }

    var body: some View {
        if let person {
            ScrollView {
                VStack(spacing: 24) {
                    PersonAvatarView(name: person.name, type: person.type, size: 100)
                        .padding(.top, 20)

                    Text(person.name)
                        .font(.title)
                        .fontWeight(.bold)

                    GroupBox("Details") {
                        VStack(alignment: .leading, spacing: 12) {
                            detailRow(label: "Type", value: person.type.rawValue.capitalized)
                            detailRow(label: "Gender", value: person.gender.rawValue.capitalized)

                            if let birthday = person.birthday {
                                detailRow(label: "Birthday", value: birthday.formatted(date: .long, time: .omitted))
                            }

                            if let age {
                                detailRow(label: "Age", value: age)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal)

                    GroupBox("Measurements") {
                        NavigationLink(destination: MeasurementListView(personId: person.id)) {
                            HStack {
                                Label("Measurements", systemImage: "chart.line.uptrend.xyaxis")
                                Spacer()
                                if !person.growthData.isEmpty {
                                    Text("\(person.growthData.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal)
                }
            }
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("Person Not Found", systemImage: "person.slash")
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}
