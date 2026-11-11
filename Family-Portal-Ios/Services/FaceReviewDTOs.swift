import Foundation

// Face review (backend/faces.go). Online only and never queued: assigning a face makes the server re-match the whole family, so the outcome is the server's to report.
// Every list is decoded with `decodeList`, since Go marshals a nil slice as `null`.

/// One face found in one photo, or in one sampled frame of a video. `personId` is 0 until someone names it or the server auto-tags it.
nonisolated struct PhotoFaceDTO: Decodable, Sendable, Identifiable, Equatable {
    let id: Int
    let photoId: Int
    let familyId: Int
    let personId: Int
    /// Relative to the photo, or to the frame at `frameMs` for a face from a video.
    let box: FaceBoxDTO
    let frameMs: Int
    /// How many of a video's frames the face was seen in; 0 for a photo.
    let frameCount: Int

    /// The frame a video face was found in, or nil for a face on a photo. The first frame is at 0, so `frameMs` alone can't tell.
    var videoFrameMs: Int? { frameCount > 0 ? frameMs : nil }

    private enum CodingKeys: String, CodingKey { case id, photoId, familyId, personId, box, frameMs, frameCount }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        photoId = try c.decode(Int.self, forKey: .photoId)
        familyId = try c.decodeIfPresent(Int.self, forKey: .familyId) ?? 0
        personId = try c.decodeIfPresent(Int.self, forKey: .personId) ?? 0
        box = try c.decodeIfPresent(FaceBoxDTO.self, forKey: .box) ?? FaceBoxDTO(left: 0, top: 0, right: 0, bottom: 0)
        frameMs = try c.decodeIfPresent(Int.self, forKey: .frameMs) ?? 0
        frameCount = try c.decodeIfPresent(Int.self, forKey: .frameCount) ?? 0
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
    /// Faces left unnamed because the person is already confirmed on their photo.
    @OrZero var skipped: Int
}

/// One look-alike group as the screen shows it. Answers shrink it in place; `id` stays the first face the server sent, so the row keeps its place.
nonisolated struct FaceGroupCard: Identifiable, Sendable {
    let id: Int
    let familyId: Int
    var faces: [PhotoFaceDTO]
    var suggestedPersonId: Int
}

/// The review with answers applied locally, as the web's Faces page does. The server re-clusters on every load, so reloading after each answer would move rows under the user's finger; it reloads only on pull to refresh, on an error, or once the lists run out.
nonisolated struct FaceReviewState: Sendable {
    let enabled: Bool
    let families: [FaceReviewFamilyDTO]
    var groups: [FaceGroupCard]
    var autoTagged: [PhotoFaceDTO]
    var unknownCount: Int
    var autoCount: Int

    init(_ review: GetFaceReviewResponseDTO) {
        enabled = review.enabled
        families = review.families
        groups = review.groups.map { FaceGroupCard(id: $0.id, familyId: $0.familyId, faces: $0.faces, suggestedPersonId: $0.suggestedPersonId) }
        autoTagged = review.autoTagged
        unknownCount = review.unknownCount
        autoCount = review.autoCount
    }

    var isEmpty: Bool { groups.isEmpty && autoTagged.isEmpty }

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

    /// Named or dismissed faces leave their group. What is left loses the suggestion, which was for the whole group.
    mutating func removeFromGroup(_ groupId: Int, faceIds: [Int]) {
        guard let index = groups.firstIndex(where: { $0.id == groupId }) else { return }
        let ids = Set(faceIds)
        let before = groups[index].faces.count
        groups[index].faces.removeAll { ids.contains($0.id) }
        unknownCount -= before - groups[index].faces.count
        if groups[index].faces.isEmpty {
            groups.remove(at: index)
        } else {
            groups[index].suggestedPersonId = 0
        }
    }

    /// A confirmed or rejected automatic tag. A rejected face goes back to the unnamed count; it shows up in a group after the next reload.
    mutating func removeAutoTag(_ faceId: Int, rejected: Bool) {
        guard let index = autoTagged.firstIndex(where: { $0.id == faceId }) else { return }
        autoTagged.remove(at: index)
        autoCount -= 1
        if rejected { unknownCount += 1 }
    }

    /// The server's report of an assign: skipped faces stay unnamed, and newly auto-tagged ones move from unnamed to check.
    mutating func recordAssigned(_ response: AssignFacesResponseDTO) {
        unknownCount += response.skipped - response.autoTagged
        autoCount += response.autoTagged
    }
}

/// The body of `RejectFaces` and `DismissFaces`.
nonisolated struct FaceIdsRequestDTO: Encodable, Sendable {
    let faceIds: [Int]
}

nonisolated struct FaceIdsResponseDTO: Decodable, Sendable {
    @OrZero var updated: Int
}
