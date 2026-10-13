import SwiftData
import SwiftUI

/// The family's Interviews page — the web's `/interviews`, under More: every child with their last interview, and Start, Continue or "Due soon" around a birthday. Everyone else (adults, mostly) waits behind a disclosure, unless they have been interviewed.
struct FamilyInterviewsView: View {
    @Environment(InterviewService.self) private var service
    @Environment(AuthService.self) private var authService
    @State private var state = ActivityScreenState<GetFamilyInterviewsResponseDTO>()
    @State private var showsOthers = false

    @Query private var people: [Person]

    var body: some View {
        ActivityScreen(state: state, read: { service.familyInterviews(today: WhenEntry.localDateString(Date())) }) { response in
            content(response)
                .padding(.horizontal)
        }
        .navigationTitle(Copy.interview.family.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ response: GetFamilyInterviewsResponseDTO) -> some View {
        let children = response.people.filter { $0.child || $0.count > 0 || $0.inProgress.id > 0 }
        let others = response.people.filter { row in !children.contains { $0.id == row.id } }
        return VStack(alignment: .leading, spacing: 16) {
            Text(Copy.interview.family.intro)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NavigationLink {
                InterviewCompareView(questionId: 0)
            } label: {
                Label(Copy.interview.compare.link, systemImage: "person.2")
                    .font(.subheadline)
            }

            if response.people.isEmpty {
                Text(Copy.interview.family.empty)
                    .foregroundStyle(.secondary)
            }
            ForEach(children) { row in
                personRow(row)
            }
            if !others.isEmpty {
                DisclosureGroup(Copy.interview.family.others, isExpanded: $showsOthers) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(others) { row in
                            personRow(row)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func personRow(_ row: FamilyInterviewRowDTO) -> some View {
        let person = row.person
        let local = people.first { $0.serverId == person.id }
        let canContribute = authService.access.canContribute(person.familyId)
        return HStack(spacing: 12) {
            NavigationLink {
                if let local {
                    PersonDetailView(personId: local.id, tab: .interviews, allowsManagementActions: false)
                }
            } label: {
                HStack(spacing: 12) {
                    if let local {
                        PersonAvatarView(person: local, size: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(row.last.id > 0
                             ? Copy.interview.family.last(
                                age: Interviews.ageYears(birthday: person.birthday, at: row.last.date),
                                date: row.last.date.displayDay().formatted(date: .long, time: .omitted),
                                count: row.count
                             )
                             : Copy.interview.family.never)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(local == nil)

            Spacer(minLength: 0)

            if row.due && row.inProgress.id == 0 {
                Text(Copy.interview.family.due)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MilestoneCategory.interview.color.opacity(0.2), in: Capsule())
            }
            if canContribute {
                NavigationLink {
                    PastInterviewView(personId: person.id)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(Copy.interview.family.typeIn)
                if row.inProgress.id > 0 {
                    NavigationLink(Copy.interview.family.continue(row.answered, row.inProgress.questionIds.count)) {
                        InterviewAskView(interviewId: row.inProgress.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    NavigationLink(Copy.interview.family.start) {
                        InterviewSetupView(personId: person.id)
                    }
                    .buttonStyle(.bordered)
                    .tint(row.due ? MilestoneCategory.interview.color : nil)
                    .controlSize(.small)
                }
            }
        }
    }
}
