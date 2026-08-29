import SwiftUI

/// How a profile photo is framed inside the avatar circle. Mirrors the web's `ProfileImage`, which scales about a percentage origin, so the same person shows the same face on both.
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
    let profilePhotoRemoteId: Int?
    let crop: ProfilePhotoCrop
    let size: CGFloat

    init(
        name: String,
        profilePhotoRemoteId: Int? = nil,
        crop: ProfilePhotoCrop = .centered,
        size: CGFloat = 44
    ) {
        self.name = name
        self.profilePhotoRemoteId = profilePhotoRemoteId
        self.crop = crop
        self.size = size
    }

    init(person: Person, size: CGFloat = 44) {
        self.init(
            name: person.name,
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

    private static let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]

    /// A stable colour per name, so a photo-less avatar is still tellable apart. Keyed on the name rather than on a relationship, which is viewer-relative: the same person would otherwise change colour depending on who was looking.
    private var backgroundColor: Color {
        var hash = 5381
        for byte in name.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        return Self.palette[abs(hash % Self.palette.count)]
    }

    var body: some View {
        avatar
            // Decorative and hidden rather than labelled: every place this appears already shows the name in text beside it, and VoiceOver would otherwise spell the initials.
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var avatar: some View {
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
