import SwiftUI
import SwiftData

/// The chip row every add form opens with — "Who is this for?" — in `FamilyGroups.chipOrder`, labelled with `chipLabels`.
/// Single-select binds an optional id and a tap on the chosen chip clears it; multi-select binds a set. A preselection is always a visible, removable chip, never a hidden default.
struct PersonChips: View {
    private enum Selection {
        case single(Binding<UUID?>)
        case multiple(Binding<Set<UUID>>)
    }

    private let selection: Selection
    /// People the row may not offer — nobody, usually.
    private let excluding: Set<UUID>

    @Query private var people: [Person]
    @Query private var relations: [PersonRelation]
    @Environment(AuthService.self) private var authService: AuthService?

    init(selection: Binding<UUID?>, excluding: Set<UUID> = []) {
        self.selection = .single(selection)
        self.excluding = excluding
    }

    init(selection: Binding<Set<UUID>>, excluding: Set<UUID> = []) {
        self.selection = .multiple(selection)
        self.excluding = excluding
    }

    static func ordered(_ people: [Person], relations: [PersonRelation], ownFamilyId: Int?) -> [Person] {
        FamilyGroups.chipOrder(people: people, relations: relations.map(\.edge), ownFamilyId: ownFamilyId)
    }

    var body: some View {
        let ordered = Self.ordered(people, relations: relations, ownFamilyId: authService?.currentUser?.familyId)
            .filter { !excluding.contains($0.id) }
        let labels = FamilyGroups.chipLabels(ordered)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ordered) { person in
                    chip(person, label: labels[person.id] ?? person.name)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func isSelected(_ person: Person) -> Bool {
        switch selection {
        case .single(let binding): return binding.wrappedValue == person.id
        case .multiple(let binding): return binding.wrappedValue.contains(person.id)
        }
    }

    private func toggle(_ person: Person) {
        switch selection {
        case .single(let binding):
            binding.wrappedValue = binding.wrappedValue == person.id ? nil : person.id
        case .multiple(let binding):
            if binding.wrappedValue.contains(person.id) {
                binding.wrappedValue.remove(person.id)
            } else {
                binding.wrappedValue.insert(person.id)
            }
        }
    }

    private func chip(_ person: Person, label: String) -> some View {
        let selected = isSelected(person)
        return Button {
            toggle(person)
        } label: {
            HStack(spacing: 6) {
                PersonAvatarView(person: person, size: 22)
                Text(label)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
