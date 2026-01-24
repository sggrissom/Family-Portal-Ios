import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema([Family.self, Person.self, GrowthData.self, Milestone.self, Photo.self, User.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])

        let family = Family(name: "Sample Family", inviteCode: "ABC123")
        container.mainContext.insert(family)

        let parent = Person(name: "Deer Daddy", type: .parent, gender: .male, birthday: date(1990, 5, 15))
        parent.family = family
        container.mainContext.insert(parent)

        let child = Person(name: "Doe", type: .child, gender: .female, birthday: date(2022, 3, 10))
        child.family = family
        container.mainContext.insert(child)

        let height1 = GrowthData(measurementType: .height, value: 28.5, unit: .inches, date: date(2023, 6, 1))
        height1.person = child
        container.mainContext.insert(height1)

        let height2 = GrowthData(measurementType: .height, value: 30.0, unit: .inches, date: date(2023, 9, 1))
        height2.person = child
        container.mainContext.insert(height2)

        let height3 = GrowthData(measurementType: .height, value: 32.5, unit: .inches, date: date(2024, 1, 15))
        height3.person = child
        container.mainContext.insert(height3)

        let weight1 = GrowthData(measurementType: .weight, value: 22.0, unit: .pounds, date: date(2023, 6, 1))
        weight1.person = child
        container.mainContext.insert(weight1)

        let weight2 = GrowthData(measurementType: .weight, value: 25.5, unit: .pounds, date: date(2024, 1, 15))
        weight2.person = child
        container.mainContext.insert(weight2)

        let milestone1 = Milestone(descriptionText: "first steps", category: .first, date: date(2023, 3, 20))
        milestone1.person = child
        container.mainContext.insert(milestone1)

        let milestone2 = Milestone(descriptionText: "said first word", category: .development, date: date(2023, 5, 10))
        milestone2.person = child
        container.mainContext.insert(milestone2)

        let milestone3 = Milestone(descriptionText: "sang a song", category: .behavior, date: date(2023, 7, 1))
        milestone3.person = child
        container.mainContext.insert(milestone3)

        let photo = Photo(title: "Snow Day", descriptionText: "playing in the snow", photoDate: date(2023, 8, 15))
        photo.taggedPeople = [child, parent]
        container.mainContext.insert(photo)

        return container
    }()

    static var sampleFamily: Family {
        let descriptor = FetchDescriptor<Family>()
        return try! container.mainContext.fetch(descriptor).first!
    }

    static var sampleParent: Person {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.type == .parent })
        return try! container.mainContext.fetch(descriptor).first!
    }

    static var sampleChild: Person {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.type == .child })
        return try! container.mainContext.fetch(descriptor).first!
    }

    static var sampleGrowthData: [GrowthData] {
        let descriptor = FetchDescriptor<GrowthData>()
        return try! container.mainContext.fetch(descriptor)
    }

    static var sampleMilestones: [Milestone] {
        let descriptor = FetchDescriptor<Milestone>()
        return try! container.mainContext.fetch(descriptor)
    }

    static var samplePhoto: Photo {
        let descriptor = FetchDescriptor<Photo>()
        return try! container.mainContext.fetch(descriptor).first!
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
