import Foundation
import Testing
@testable import Family_Portal_Ios

@Suite("Sync DTO decoding")
struct SyncDTODecodingTests {

    static func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - PersonDTO

    @Test("Decodes a Person as the backend marshals it")
    func decodesPerson() throws {
        let json = """
        {
          "id": 12,
          "familyId": 7,
          "name": "Rowan",
          "gender": 2,
          "birthday": "2019-08-04T00:00:00Z",
          "age": "6 years",
          "relationship": "daughter",
          "profilePhotoId": 88,
          "profileCropX": 50,
          "profileCropY": 42.5,
          "profileCropScale": 1.25,
          "isPregnancy": false
        }
        """
        let dto = try APIClient.decode(PersonDTO.self, from: Data(json.utf8))

        #expect(dto.id == 12)
        #expect(dto.familyId == 7)
        #expect(dto.name == "Rowan")
        #expect(dto.gender == 2)
        #expect(dto.relationship == "daughter")
        #expect(dto.age == "6 years")
        #expect(dto.profilePhotoId == 88)
        #expect(dto.profileCropY == 42.5)
        #expect(dto.profileCropScale == 1.25)
        #expect(abs(dto.birthday.timeIntervalSince(Self.utc(2019, 8, 4))) < 1)
    }

    @Test("Maps a decoded Person onto the local model")
    func mapsPersonToModel() throws {
        let json = """
        {
          "id": 12, "familyId": 7, "name": "Rowan", "gender": 2,
          "birthday": "2019-08-04T00:00:00Z", "age": "6 years",
          "relationship": "daughter",
          "profilePhotoId": 88, "profileCropX": 50, "profileCropY": 50,
          "profileCropScale": 1, "isPregnancy": false
        }
        """
        let person = personFromDTO(try APIClient.decode(PersonDTO.self, from: Data(json.utf8)))

        #expect(person.remoteId == "12")
        #expect(person.name == "Rowan")
        #expect(person.relationship == "daughter")
        #expect(person.gender == .other)
        #expect(person.profilePhotoId == 88)
    }

    @Test("A person the relationship graph doesn't reach carries no relationship")
    func unrelatedPersonHasNoRelationship() throws {
        // The server omits the key rather than sending "", and `GetFamilyTimeline` labels everyone it can, so an absent key means unrelated rather than unknown.
        let json = """
        {
          "id": 12, "familyId": 7, "name": "Rowan", "gender": 2,
          "birthday": "2019-08-04T00:00:00Z", "age": "6 years", "isPregnancy": false
        }
        """
        let person = personFromDTO(try APIClient.decode(PersonDTO.self, from: Data(json.utf8)))

        #expect(person.relationship == nil)
    }

    // MARK: - GrowthDataDTO

    @Test("Decodes GrowthData and maps units")
    func decodesGrowthData() throws {
        let json = """
        {
          "id": 501,
          "personId": 12,
          "familyId": 7,
          "measurementType": 1,
          "value": 18.4,
          "unit": "kg",
          "measurementDate": "2026-01-09T00:00:00Z",
          "createdAt": "2026-01-09T18:22:41.482913Z"
        }
        """
        let dto = try APIClient.decode(GrowthDataDTO.self, from: Data(json.utf8))

        #expect(dto.id == 501)
        #expect(dto.measurementType == 1)
        #expect(dto.value == 18.4)
        #expect(dto.unit == "kg")
        #expect(abs(dto.measurementDate.timeIntervalSince(Self.utc(2026, 1, 9))) < 1)

        let model = growthDataFromDTO(dto)
        #expect(model.remoteId == "501")
        #expect(model.measurementType == .weight)
        #expect(model.unit == .kilograms)
    }

    // MARK: - MilestoneDTO

    @Test("Decodes a Milestone, including the `description` key rename")
    func decodesMilestone() throws {
        let json = """
        {
          "id": 77,
          "personId": 12,
          "familyId": 7,
          "description": "First full sentence",
          "category": "language",
          "milestoneDate": "2021-05-02T00:00:00Z",
          "createdAt": "2021-05-03T11:04:00Z",
          "photoIds": [4, 9]
        }
        """
        let dto = try APIClient.decode(MilestoneDTO.self, from: Data(json.utf8))

        #expect(dto.id == 77)
        #expect(dto.descriptionText == "First full sentence")
        #expect(dto.category == "language")
        #expect(dto.photoIds == [4, 9])
    }

    @Test("Tolerates photoIds being omitted, which Go does via omitempty")
    func decodesMilestoneWithoutPhotoIds() throws {
        let json = """
        {
          "id": 77, "personId": 12, "familyId": 7,
          "description": "Rolled over", "category": "physical",
          "milestoneDate": "2020-01-02T00:00:00Z",
          "createdAt": "2020-01-02T11:04:00Z"
        }
        """
        let dto = try APIClient.decode(MilestoneDTO.self, from: Data(json.utf8))
        #expect(dto.photoIds.isEmpty)
    }

    // MARK: - ImageDTO

    @Test("Decodes an Image, ignoring fields iOS doesn't model")
    func decodesImage() throws {
        let json = """
        {
          "id": 4,
          "familyId": 7,
          "ownerUserId": 33,
          "originalFilename": "IMG_2201.HEIC",
          "mimeType": "image/heic",
          "fileSize": 2481003,
          "width": 4032,
          "height": 3024,
          "filePath": "families/7/4.heic",
          "title": "Beach day",
          "description": "First time in the ocean",
          "photoDate": "2025-07-19T16:02:11Z",
          "createdAt": "2025-07-19T16:40:02.10012Z",
          "status": 1,
          "analysisStatus": 2,
          "tagIds": [3]
        }
        """
        let dto = try APIClient.decode(ImageDTO.self, from: Data(json.utf8))

        #expect(dto.id == 4)
        #expect(dto.title == "Beach day")
        #expect(dto.descriptionText == "First time in the ocean")
        // status 1 means the server is still processing and serves a placeholder.
        #expect(dto.status == 1)
        #expect(abs(dto.photoDate.timeIntervalSince(Self.utc(2025, 7, 19, 16, 2) + 11)) < 1)
    }

    // MARK: - UpdatePhoto request (P0 #6)

    @Test("UpdatePhoto request matches backend/photos.go UpdatePhotoRequest")
    func updatePhotoRequestKeys() throws {
        let data = try JSONEncoder().encode(
            UpdatePhotoRequestDTO(
                id: 4,
                title: "Beach day",
                description: "First time in the ocean",
                inputType: "date",
                photoDate: "2025-07-19"
            )
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["id"] as? Int == 4)
        #expect(object["title"] as? String == "Beach day")
        #expect(object["description"] as? String == "First time in the ocean")
        #expect(object["inputType"] as? String == "date")
        #expect(object["photoDate"] as? String == "2025-07-19")
    }
}
