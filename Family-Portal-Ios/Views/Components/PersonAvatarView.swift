import SwiftUI

struct PersonAvatarView: View {
    let name: String
    let type: PersonType
    let profilePhotoRemoteId: Int?
    let size: CGFloat

    init(name: String, type: PersonType, profilePhotoRemoteId: Int? = nil, size: CGFloat = 44) {
        self.name = name
        self.type = type
        self.profilePhotoRemoteId = profilePhotoRemoteId
        self.size = size
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
