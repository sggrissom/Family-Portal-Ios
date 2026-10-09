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
    @OrZero var familyId: Int
    @OrZero var faces: [PhotoFaceDTO]
    /// 0 when nobody is close enough to suggest.
    @OrZero var suggestedPersonId: Int

    /// The web keys a group by its first face too: groups are re-clustered on every load, so nothing else is stable.
    var id: Int { faces.first?.id ?? 0 }
}

/// A family the caller can label faces in, with the people a face can be named as — sorted by name on the server.
nonisolated struct FaceReviewFamilyDTO: Decodable, Sendable {
    let familyId: Int
    @OrZero var name: String
    @OrZero var people: [PersonDTO]
}

nonisolated struct GetFaceReviewResponseDTO: Decodable, Sendable {
    /// False where the server isn't running face recognition; there is then nothing to review.
    @OrZero var enabled: Bool
    @OrZero var groups: [FaceGroupDTO]
    /// Auto-tagged faces, least certain first, capped by the server.
    @OrZero var autoTagged: [PhotoFaceDTO]
    @OrZero var families: [FaceReviewFamilyDTO]
    @OrZero var unknownCount: Int
    @OrZero var autoCount: Int

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
    @OrZero var assigned: Int
    /// Other photos the server tagged on its own once it learned the face.
    @OrZero var autoTagged: Int
}

/// The body of `RejectFaces` and `DismissFaces`.
nonisolated struct FaceIdsRequestDTO: Encodable, Sendable {
    let faceIds: [Int]
}

nonisolated struct FaceIdsResponseDTO: Decodable, Sendable {
    @OrZero var updated: Int
}
