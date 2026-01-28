import SwiftUI

struct PersonRowView: View {
    let name: String
    let type: PersonType
    let birthday: Date?
    let profilePhotoRemoteId: Int?
    let avatarSize: CGFloat

    init(
        name: String,
        type: PersonType,
        birthday: Date?,
        profilePhotoRemoteId: Int?,
        avatarSize: CGFloat = 56
    ) {
        self.name = name
        self.type = type
        self.birthday = birthday
        self.profilePhotoRemoteId = profilePhotoRemoteId
        self.avatarSize = avatarSize
    }

    private var ageText: String? {
        guard let birthday else { return nil }
        return "Age \(AgeCalculator.age(from: birthday))"
    }

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatarView(
                name: name,
                type: type,
                profilePhotoRemoteId: profilePhotoRemoteId,
                size: avatarSize
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(type.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let ageText {
                        Text(ageText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
