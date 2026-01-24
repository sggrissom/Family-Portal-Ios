import SwiftUI

struct PersonRowView: View {
    let name: String
    let type: PersonType
    let birthday: Date?

    private var birthdayText: String? {
        guard let birthday else { return nil }
        return birthday.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatarView(name: name, type: type)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(type.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let birthdayText {
                        Text(birthdayText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
