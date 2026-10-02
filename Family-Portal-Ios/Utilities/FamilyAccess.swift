import Foundation

/// What the signed-in account may do in each family, read from the auth response's `families` — mirrors frontend/lib/authCache.ts so a view-only member sees the same screens on the phone as on the web: everything, with no add, edit or delete controls.
/// The server enforces all of this; hiding the controls only spares a view-only member a button that can only fail.
struct FamilyAccess {
    /// The backend's `AccessLevel` (backend/access.go).
    static let view = 1
    static let contribute = 2
    static let admin = 3

    let families: [FamilyRefDTO]
    /// The account's own family, which a record with no family of its own yet — anyone added offline, or anything pulled before the upgrade that started recording it — is read as belonging to.
    let primaryFamilyId: Int?

    init(families: [FamilyRefDTO], primaryFamilyId: Int?) {
        // A session cached by a build that did not keep `families` has only the primary id. Like the web, read that as admin of it until the next refresh brings the real roles.
        if families.isEmpty, let primaryFamilyId, primaryFamilyId != 0 {
            self.families = [FamilyRefDTO(id: primaryFamilyId, role: Self.admin, isPrimary: true)]
        } else {
            self.families = families
        }
        self.primaryFamilyId = primaryFamilyId
    }

    init(auth: AuthResponseDTO?) {
        self.init(families: auth?.families ?? [], primaryFamilyId: auth?.familyId)
    }

    /// The role in one family; `nil` means the account's own. 0 for a family the account only sees through a link.
    func role(in familyId: Int?) -> Int {
        guard let id = familyId ?? primaryFamilyId else { return 0 }
        return families.first { $0.id == id }?.role ?? 0
    }

    func canContribute(_ familyId: Int?) -> Bool {
        role(in: familyId) >= Self.contribute
    }

    func canAdmin(_ familyId: Int?) -> Bool {
        role(in: familyId) >= Self.admin
    }

    var contributableFamilies: [FamilyRefDTO] {
        families.filter { $0.role >= Self.contribute }
    }

    /// Whether any **+** belongs on screen at all.
    var canContributeAnywhere: Bool {
        !contributableFamilies.isEmpty
    }

    func canContribute(to person: Person) -> Bool {
        canContribute(person.familyRemoteId)
    }

    /// Records are filed under their person's family.
    func canContribute(to milestone: Milestone) -> Bool {
        canContribute(milestone.person?.familyRemoteId)
    }

    func canContribute(to measurement: GrowthData) -> Bool {
        canContribute(measurement.person?.familyRemoteId)
    }

    func canContribute(to photo: Photo) -> Bool {
        canContribute(photo.familyRemoteId)
    }

    /// Deleting a photo takes an admin, as on the web.
    func canDelete(_ photo: Photo) -> Bool {
        canAdmin(photo.familyRemoteId)
    }

    /// No session — previews, and the moment between sign-out and the login screen. Nothing is offered.
    static let signedOut = FamilyAccess(families: [], primaryFamilyId: nil)
}

extension AuthService {
    var access: FamilyAccess { FamilyAccess(auth: currentUser) }
}

extension Optional where Wrapped == AuthService {
    /// For the views that read `AuthService` optionally so previews can omit it.
    var access: FamilyAccess { self?.access ?? .signedOut }
}
