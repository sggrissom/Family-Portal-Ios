import SwiftUI

/// The family's books on a shelf, newest-edited first — the web's `/books`. Pushed from the account menu and from a person's page.
/// Making and editing books is web-only for now, so the shelf holds only what has been saved there.
struct BooksView: View {
    @Environment(BookService.self) private var service

    @State private var state = ActivityScreenState<ListBooksResponseDTO>()

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 18, alignment: .top)]

    var body: some View {
        ActivityScreen(state: state, read: { service.books() }) { response in
            VStack(alignment: .leading, spacing: 20) {
                Text("Turn your family's memories into a story.")
                    .font(BookType.serif(.body).italic())
                    .foregroundStyle(.secondary)

                if response.books.isEmpty {
                    ContentUnavailableView {
                        Label("No Books Yet", systemImage: "book.closed")
                    } description: {
                        Text("Books are made on the web for now — a first year, a year of one person, a family year, or any stretch of dates. Once one is saved, it can be read here.")
                    }
                    .padding(.top, 24)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                        ForEach(response.books) { book in
                            NavigationLink(value: AppRoute.book(id: book.id, title: book.title)) {
                                BookShelfItem(book: book)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(Copy.account.books)
    }
}

/// A book standing on the shelf: its cover photo bound with a shaded spine, or a cloth cover with the title set on it when there is no photo.
private struct BookShelfItem: View {
    let book: BookSummaryDTO

    private var cover: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
    }

    private var subtitle: String {
        let dates = BookDay.bookDates(start: book.startDate, end: book.endDate)
        return book.personNames.count > 1 ? "\(BookAssembler.joinNames(book.personNames)) · \(dates)" : dates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    if book.coverPhotoId > 0 {
                        RemotePhotoView(remoteId: book.coverPhotoId, size: .medium)
                    } else {
                        cloth
                    }
                }
                .overlay(alignment: .leading) {
                    // The spine: a shadowed fold a few points in from the binding edge.
                    LinearGradient(
                        colors: [.black.opacity(0.22), .black.opacity(0.04), .white.opacity(0.10), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 12)
                }
                .clipShape(cover)
                .shadow(color: .black.opacity(0.16), radius: 9, x: 0, y: 6)

            Text(book.title)
                .font(BookType.serif(.subheadline).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var cloth: some View {
        ZStack {
            LinearGradient(
                colors: [BookPalette.rule, BookPalette.inkSoft.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 10) {
                Text(book.title)
                    .font(BookType.serif(.headline))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(BookPalette.ink)
                Rectangle()
                    .fill(BookPalette.ink.opacity(0.4))
                    .frame(width: 28, height: 1)
            }
            .padding(18)
        }
    }
}
