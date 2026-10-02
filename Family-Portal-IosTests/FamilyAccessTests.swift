import Foundation
import Testing
@testable import Family_Portal_Ios

/// The cases from frontend/lib/authCache.test.ts, plus the records that read their family through their person.
@MainActor
@Suite("Family access")
struct FamilyAccessTests {

    /// Admin of their own family (3), contributor to 5, view-only in 9.
    private static let access = FamilyAccess(
        families: [
            FamilyRefDTO(id: 3, role: FamilyAccess.admin, isPrimary: true),
            FamilyRefDTO(id: 5, role: FamilyAccess.contribute),
            FamilyRefDTO(id: 9, role: FamilyAccess.view),
        ],
        primaryFamilyId: 3
    )

    private static func person(familyId: Int?) -> Person {
        let person = Person(name: "Ada", gender: .female)
        person.familyRemoteId = familyId
        return person
    }

    @Test("Roles gate contributing and administering family by family")
    func roles() {
        let access = Self.access

        #expect(access.canContribute(3) && access.canAdmin(3))
        #expect(access.canContribute(5) && !access.canAdmin(5))
        #expect(!access.canContribute(9) && !access.canAdmin(9))
        // A family seen only through a link carries no role at all.
        #expect(access.role(in: 42) == 0)
        #expect(!access.canContribute(42))
    }

    @Test("A record with no family yet is read as the account's own")
    func missingFamilyIsPrimary() {
        #expect(Self.access.canAdmin(nil))

        let viewer = FamilyAccess(families: [FamilyRefDTO(id: 9, role: FamilyAccess.view, isPrimary: true)], primaryFamilyId: 9)
        #expect(!viewer.canContribute(nil))
    }

    @Test("Any + is shown only to an account that can contribute somewhere")
    func contributeAnywhere() {
        #expect(Self.access.canContributeAnywhere)
        #expect(Self.access.contributableFamilies.map(\.id) == [3, 5])

        let viewer = FamilyAccess(families: [FamilyRefDTO(id: 9, role: FamilyAccess.view, isPrimary: true)], primaryFamilyId: 9)
        #expect(!viewer.canContributeAnywhere)
        #expect(!FamilyAccess.signedOut.canContributeAnywhere)
    }

    @Test("A session cached before roles were kept is admin of its own family until the refresh")
    func legacyCachedSession() {
        let legacy = FamilyAccess(families: [], primaryFamilyId: 3)

        #expect(legacy.canAdmin(3))
        #expect(legacy.canAdmin(nil))
        #expect(!legacy.canContribute(5))
    }

    @Test("Milestones and measurements follow their person's family; photos their own")
    func records() {
        let access = Self.access
        let ours = Self.person(familyId: 3)
        let grandparents = Self.person(familyId: 9)

        let milestone = Milestone(descriptionText: "Walked", category: .development, date: Date())
        milestone.person = grandparents
        #expect(!access.canContribute(to: milestone))
        milestone.person = ours
        #expect(access.canContribute(to: milestone))

        let height = GrowthData(measurementType: .height, value: 30, unit: .inches, date: Date())
        height.person = grandparents
        #expect(!access.canContribute(to: height))

        let photo = Photo(title: "", descriptionText: "", photoDate: Date())
        photo.familyRemoteId = 5
        #expect(access.canContribute(to: photo))
        // Deleting a photo takes an admin.
        #expect(!access.canDelete(photo))
        photo.familyRemoteId = 3
        #expect(access.canDelete(photo))
    }
}
