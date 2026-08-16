import SwiftUI

/// How a profile photo is framed inside the avatar circle. Mirrors the web
/// client's `ProfileImage`, which scales the image about a percentage origin
/// (`transform: scale(s); transform-origin: x% y%`), so the same person shows
/// the same face on both.
struct ProfilePhotoCrop: Equatable {
    let x: Double
    let y: Double
    let scale: Double

    static let centered = ProfilePhotoCrop(x: 50, y: 50, scale: 1)

    /// Missing values mean "never cropped" and fall back to a centred 1× frame.
    init(x: Double?, y: Double?, scale: Double?) {
        self.x = x ?? 50
        self.y = y ?? 50
        self.scale = max(scale ?? 1, 1)
    }

    var anchor: UnitPoint {
        UnitPoint(x: x / 100, y: y / 100)
    }
}

struct PersonAvatarView: View {
    let name: String
    let type: PersonType
    let profilePhotoRemoteId: Int?
    let crop: ProfilePhotoCrop
    let size: CGFloat

    init(
        name: String,
        type: PersonType,
        profilePhotoRemoteId: Int? = nil,
        crop: ProfilePhotoCrop = .centered,
        size: CGFloat = 44
    ) {
        self.name = name
        self.type = type
        self.profilePhotoRemoteId = profilePhotoRemoteId
        self.crop = crop
        self.size = size
    }

    /// The usual call: everything the avatar needs already lives on the person,
    /// including the crop, which is easy to forget when it is passed field by
    /// field.
    init(person: Person, size: CGFloat = 44) {
        self.init(
            name: person.name,
            type: person.type,
            profilePhotoRemoteId: person.profilePhotoId,
            crop: ProfilePhotoCrop(
                x: person.profileCropX,
                y: person.profileCropY,
                scale: person.profileCropScale
            ),
            size: size
        )
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last!.prefix(1) : ""
        return String(first + last).uppercased()
    }

    private var backgroundColor: Color {
        switch type {
        case .parent: return .blue
        case .child: return .green
        }
    }

    var body: some View {
        if let profilePhotoRemoteId {
            ZStack {
                initialsView
                RemotePhotoView(remoteId: profilePhotoRemoteId, size: .thumb)
                    .frame(width: size, height: size)
                    .scaleEffect(crop.scale, anchor: crop.anchor)
                    .clipShape(Circle())
            }
            .frame(width: size, height: size)
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(backgroundColor)
            .clipShape(Circle())
    }
}
