import Foundation
import Testing
@testable import Family_Portal_Ios

/// Ports frontend/lib/familyPage.test.ts, plus decoding of the settings read.
@MainActor
@Suite("Family page")
struct FamilyPageTests {

    private static func person(
        _ id: Int, _ name: String, ageYears: Int? = nil, photoId: Int = 0,
        cropX: Double = 0, cropY: Double = 0, cropScale: Double = 0
    ) -> FamilyPagePersonDTO {
        FamilyPagePersonDTO(
            id: id, name: name, ageYears: ageYears, profilePhotoId: photoId,
            profileCropX: cropX, profileCropY: cropY, profileCropScale: cropScale
        )
    }

    private static let people = [
        person(1, "Ada Smith", ageYears: 7, photoId: 40, cropX: 30, cropY: 60, cropScale: 2),
        person(2, "Ben Smith", ageYears: 4),
        person(3, "Cy"),
    ]

    private static func form() -> FamilyPageSettingsDTO {
        FamilyPageSettingsDTO(slug: "smiths", title: "The Smiths")
    }

    @Test("Adds people with their first name and keeps the roster order")
    func addsInRosterOrder() {
        var form = Self.form()
        FamilyPage.toggleMember(&form, people: Self.people, person: Self.people[1])
        FamilyPage.toggleMember(&form, people: Self.people, person: Self.people[0])
        #expect(form.members.map(\.personId) == [1, 2])
        #expect(form.members.map(\.name) == ["Ada", "Ben"])
        #expect(form.members.allSatisfy { !$0.showAge && !$0.showPhoto && $0.line.isEmpty })
    }

    @Test("Removing someone keeps the others' edits")
    func removeKeepsEdits() {
        var form = Self.form()
        FamilyPage.toggleMember(&form, people: Self.people, person: Self.people[0])
        FamilyPage.toggleMember(&form, people: Self.people, person: Self.people[1])
        form.members[1].line = "Builds forts"
        FamilyPage.toggleMember(&form, people: Self.people, person: Self.people[0])
        #expect(form.members == [
            FamilyPageMemberSettingsDTO(personId: 2, name: "Ben", line: "Builds forts", showAge: false, showPhoto: false),
        ])
    }

    @Test("Photos stop at the limit and toggle off")
    func photoLimit() {
        var form = Self.form()
        for id in 1...(FamilyPage.maxPhotos + 2) {
            FamilyPage.togglePhoto(&form, photoId: id)
        }
        #expect(form.photoIds.count == FamilyPage.maxPhotos)
        FamilyPage.togglePhoto(&form, photoId: 1)
        #expect(!form.photoIds.contains(1))
    }

    @Test("The preview shows only the choices on the form")
    func preview() {
        var form = Self.form()
        form.intro = "  Hi there  "
        for person in Self.people {
            FamilyPage.toggleMember(&form, people: Self.people, person: person)
        }
        form.members[0].showAge = true
        form.members[0].showPhoto = true
        form.members[1].showPhoto = true
        form.members[2].name = "  "
        form.photoIds = [9]

        #expect(FamilyPage.preview(form, people: Self.people) == FamilyPage.Preview(
            title: "The Smiths",
            intro: "Hi there",
            members: [
                .init(name: "Ada", line: "", ageYears: 7, photoId: 40, cropX: 30, cropY: 60, cropScale: 2),
                .init(name: "Ben", line: "", ageYears: nil, photoId: nil, cropX: 0, cropY: 0, cropScale: 0),
                .init(name: "Cy", line: "", ageYears: nil, photoId: nil, cropX: 0, cropY: 0, cropScale: 0),
            ],
            photoIds: [9]
        ))
    }

    @Test("Members no longer on the roster drop out of the preview")
    func previewDropsRemoved() {
        var form = Self.form()
        FamilyPage.toggleMember(&form, people: Self.people, person: Self.people[0])
        #expect(FamilyPage.preview(form, people: Array(Self.people.dropFirst())).members.isEmpty)
    }

    @Test("Settings decode published and unpublished, with missing fields")
    func decodesSettings() throws {
        let published = """
        {"familyId":5,"canEdit":true,"published":true,"url":"https://example.com/f/smiths",
         "publishedAt":"2026-11-22T19:00:00Z","publishedByName":"Sam",
         "settings":{"slug":"smiths","indexable":false,"title":"The Smiths","intro":"Hi",
           "members":[{"personId":1,"name":"Ada","line":"","showAge":true,"showPhoto":false}],"photoIds":[9]},
         "people":[{"id":1,"name":"Ada Smith","ageYears":7,"profilePhotoId":40,"profileCropX":30,"profileCropY":60,"profileCropScale":2},
                   {"id":2,"name":"Baby","profilePhotoId":0,"profileCropX":0,"profileCropY":0,"profileCropScale":0}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let page = try decoder.decode(FamilyPageSettingsResponseDTO.self, from: Data(published.utf8))
        #expect(page.published && page.canEdit)
        #expect(page.publishedAt != nil)
        #expect(page.settings.members.first?.showAge == true)
        #expect(page.settings.photoIds == [9])
        #expect(page.people.map(\.ageYears) == [7, nil])

        let unpublished = """
        {"familyId":5,"canEdit":false,"published":false,"url":"","publishedByName":"",
         "settings":{"slug":"smiths","indexable":false,"title":"The Smiths","intro":"","members":null,"photoIds":null},
         "people":null}
        """
        let empty = try decoder.decode(FamilyPageSettingsResponseDTO.self, from: Data(unpublished.utf8))
        #expect(!empty.published && empty.publishedAt == nil)
        #expect(empty.settings.members.isEmpty && empty.settings.photoIds.isEmpty && empty.people.isEmpty)
    }

    @Test("Publishing sends the form as the server reads it")
    func encodesPublish() throws {
        var form = Self.form()
        FamilyPage.toggleMember(&form, people: Self.people, person: Self.people[0])
        let body = try JSONEncoder().encode(PublishFamilyPageRequestDTO(familyId: 5, settings: form))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let settings = try #require(json["settings"] as? [String: Any])
        #expect(json["familyId"] as? Int == 5)
        #expect(Set(settings.keys) == ["slug", "indexable", "title", "intro", "members", "photoIds"])
        let member = try #require((settings["members"] as? [[String: Any]])?.first)
        #expect(Set(member.keys) == ["personId", "name", "line", "showAge", "showPhoto"])
    }
}
