import Foundation

/// Port of frontend/lib/familyPage.ts: the editor's draft and its preview.
nonisolated enum FamilyPage {
    static let maxPhotos = 6

    static func defaultName(_ fullName: String) -> String {
        fullName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? fullName
    }

    /// Adds or removes a person, keeping the roster's order and everyone else's edits.
    static func toggleMember(
        _ form: inout FamilyPageSettingsDTO,
        people: [FamilyPagePersonDTO],
        person: FamilyPagePersonDTO
    ) {
        var byId = Dictionary(form.members.map { ($0.personId, $0) }, uniquingKeysWith: { first, _ in first })
        if byId[person.id] != nil {
            byId[person.id] = nil
        } else {
            byId[person.id] = FamilyPageMemberSettingsDTO(
                personId: person.id,
                name: defaultName(person.name),
                line: "",
                showAge: false,
                showPhoto: false
            )
        }
        form.members = people.compactMap { byId[$0.id] }
    }

    static func togglePhoto(_ form: inout FamilyPageSettingsDTO, photoId: Int) {
        if let index = form.photoIds.firstIndex(of: photoId) {
            form.photoIds.remove(at: index)
        } else if form.photoIds.count < maxPhotos {
            form.photoIds.append(photoId)
        }
    }

    struct PreviewMember: Equatable {
        let name: String
        let line: String
        let ageYears: Int?
        let photoId: Int?
        let cropX: Double
        let cropY: Double
        let cropScale: Double
    }

    struct Preview: Equatable {
        let title: String
        let intro: String
        let members: [PreviewMember]
        let photoIds: [Int]
    }

    /// What visitors will see, drawn from the form. People no longer on the roster drop out.
    static func preview(_ form: FamilyPageSettingsDTO, people: [FamilyPagePersonDTO]) -> Preview {
        let byId = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let members: [PreviewMember] = form.members.compactMap { member in
            guard let person = byId[member.personId] else { return nil }
            let showsPhoto = member.showPhoto && person.profilePhotoId > 0
            let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return PreviewMember(
                name: name.isEmpty ? defaultName(person.name) : name,
                line: member.line.trimmingCharacters(in: .whitespacesAndNewlines),
                ageYears: member.showAge ? person.ageYears : nil,
                photoId: showsPhoto ? person.profilePhotoId : nil,
                cropX: showsPhoto ? person.profileCropX : 0,
                cropY: showsPhoto ? person.profileCropY : 0,
                cropScale: showsPhoto ? person.profileCropScale : 0
            )
        }
        return Preview(
            title: form.title.trimmingCharacters(in: .whitespacesAndNewlines),
            intro: form.intro.trimmingCharacters(in: .whitespacesAndNewlines),
            members: members,
            photoIds: form.photoIds
        )
    }
}
