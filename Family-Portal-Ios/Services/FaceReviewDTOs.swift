import Foundation

// Face review (backend/faces.go). Online only and never queued: assigning a face makes the server re-match the whole family, so the outcome is the server's to report.
// Every list is decoded with `decodeList`, since Go marshals a nil slice as `null`.

/// One face found in one photo. `personId` is 0 until someone names it or the server auto-tags it.
nonisolated struct PhotoFaceDTO: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let photoId: Int
    let familyId: Int
    let personId: Int
    let box: FaceBoxDTO

    private enum CodingKeys: String, CodingKey { case id, photoId, familyId, personId, box }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        photoId = try c.decode(Int.self, forKey: .photoId)
        familyId = try c.decodeIfPresent(Int.self, forKey: .familyId) ?? 0
        personId = try c.decodeIfPresent(Int.self, forKey: .personId) ?? 0
        box = try c.decodeIfPresent(FaceBoxDTO.self, forKey: .box) ?? FaceBoxDTO(left: 0, top: 0, right: 0, bottom: 0)
    }
}

/// Unnamed faces the server thinks are the same person, with its best guess when one is close enough.
nonisolated struct FaceGroupDTO: Decodable, Sendable, Identifiable {
    let familyId: Int
    let faces: [PhotoFaceDTO]
    /// 0 when nobody is close enough to suggest.
    let suggestedPersonId: Int

    /// The web keys a group by its first face too: groups are re-clustered on every load, so nothing else is stable.
    var id: Int { faces.first?.id ?? 0 }

    private enum CodingKeys: String, CodingKey { case familyId, faces, suggestedPersonId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        familyId = try c.decodeIfPresent(Int.self, forKey: .familyId) ?? 0
        faces = try c.decodeList(PhotoFaceDTO.self, forKey: .faces)
        suggestedPersonId = try c.decodeIfPresent(Int.self, forKey: .suggestedPersonId) ?? 0
    }
}

/// A family the caller can label faces in, with the people a face can be named as — sorted by name on the server.
nonisolated struct FaceReviewFamilyDTO: Decodable, Sendable {
    let familyId: Int
    let name: String
    let people: [PersonDTO]

    private enum CodingKeys: String, CodingKey { case familyId, name, people }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        familyId = try c.decode(Int.self, forKey: .familyId)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        people = try c.decodeList(PersonDTO.self, forKey: .people)
    }
}

nonisolated struct GetFaceReviewResponseDTO: Decodable, Sendable {
    /// False where the server isn't running face recognition; there is then nothing to review.
    let enabled: Bool
    let groups: [FaceGroupDTO]
    /// Auto-tagged faces, least certain first, capped by the server.
    let autoTagged: [PhotoFaceDTO]
    let families: [FaceReviewFamilyDTO]
    let unknownCount: Int
    let autoCount: Int

    private enum CodingKeys: String, CodingKey { case enabled, groups, autoTagged, families, unknownCount, autoCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        groups = try c.decodeList(FaceGroupDTO.self, forKey: .groups)
        autoTagged = try c.decodeList(PhotoFaceDTO.self, forKey: .autoTagged)
        families = try c.decodeList(FaceReviewFamilyDTO.self, forKey: .families)
        unknownCount = try c.decodeIfPresent(Int.self, forKey: .unknownCount) ?? 0
        autoCount = try c.decodeIfPresent(Int.self, forKey: .autoCount) ?? 0
    }

    func people(inFamily familyId: Int) -> [PersonDTO] {
        families.first { $0.familyId == familyId }?.people ?? []
    }

    func familyName(_ familyId: Int) -> String? {
        families.first { $0.familyId == familyId }?.name
    }

    func personName(_ personId: Int) -> String {
        for family in families {
            if let person = family.people.first(where: { $0.id == personId }) {
                return person.name
            }
        }
        return "Unknown"
    }
}

nonisolated struct AssignFacesRequestDTO: Encodable, Sendable {
    let faceIds: [Int]
    let personId: Int
}

nonisolated struct AssignFacesResponseDTO: Decodable, Sendable {
    let assigned: Int
    /// Other photos the server tagged on its own once it learned the face.
    let autoTagged: Int

    private enum CodingKeys: String, CodingKey { case assigned, autoTagged }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assigned = try c.decodeIfPresent(Int.self, forKey: .assigned) ?? 0
        autoTagged = try c.decodeIfPresent(Int.self, forKey: .autoTagged) ?? 0
    }
}

/// The body of `RejectFaces` and `DismissFaces`.
nonisolated struct FaceIdsRequestDTO: Encodable, Sendable {
    let faceIds: [Int]
}

nonisolated struct FaceIdsResponseDTO: Decodable, Sendable {
    let updated: Int

    private enum CodingKeys: String, CodingKey { case updated }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        updated = try c.decodeIfPresent(Int.self, forKey: .updated) ?? 0
    }
}
