import SwiftUI

struct PersonRowView: View {
    let name: String
    let type: PersonType
    let birthday: Date?
    /// Travels with `birthday`, which it qualifies: the same date is a due date
    /// or a birth date depending on it, and the two must not be passed apart.
    let isPregnancy: Bool
    let profilePhotoRemoteId: Int?
    let crop: ProfilePhotoCrop
    let avatarSize: CGFloat

    init(
        name: String,
        type: PersonType,
        birthday: Date?,
        isPregnancy: Bool = false,
        profilePhotoRemoteId: Int?,
        crop: ProfilePhotoCrop = .centered,
        avatarSize: CGFloat = 80
    ) {
        self.name = name
        self.type = type
        self.birthday = birthday
        self.isPregnancy = isPregnancy
        self.profilePhotoRemoteId = profilePhotoRemoteId
        self.crop = crop
        self.avatarSize = avatarSize
    }

    init(person: Person, avatarSize: CGFloat = 80) {
        self.init(
            name: person.name,
            type: person.type,
            birthday: person.birthday,
            isPregnancy: person.isPregnancy,
            profilePhotoRemoteId: person.profilePhotoId,
            crop: ProfilePhotoCrop(
                x: person.profileCropX,
                y: person.profileCropY,
                scale: person.profileCropScale
            ),
            avatarSize: avatarSize
        )
    }

    private var ageText: String? {
        guard let birthday else { return nil }
        if isPregnancy {
            // "Age 32 weeks" reads badly for someone not yet born.
            return AgeCalculator.age(from: birthday, isPregnancy: true)
        }
        return "Age \(AgeCalculator.age(from: birthday))"
    }

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatarView(
                name: name,
                type: type,
                profilePhotoRemoteId: profilePhotoRemoteId,
                crop: crop,
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
