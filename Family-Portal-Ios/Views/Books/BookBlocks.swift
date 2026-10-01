import Charts
import SwiftUI

/// The book's own paper and ink, as `.book-page` sets them on the web: warm paper in light, a quiet charcoal in dark. A book reads as a keepsake, not as another screen of the app, so it does not take the system background.
enum BookPalette {
    static let paper = Color(light: 0xFBF8F2, dark: 0x17181B)
    static let ink = Color(light: 0x2C2721, dark: 0xEBE5DA)
    static let inkSoft = Color(light: 0x7B7064, dark: 0xA59C8E)
    static let rule = Color(light: 0xE6DDCF, dark: 0x2E3036)
    static let mat = Color(light: 0xFFFFFF, dark: 0x22242A)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

/// The type the book is set in: the system serif for reading, a small sans for the dates and labels around it.
enum BookType {
    static func serif(_ style: Font.TextStyle) -> Font { .system(style, design: .serif) }
    static let label = Font.system(.caption2, design: .default).weight(.semibold)
    static let when = Font.system(.caption, design: .default)
}

// MARK: - Photos

/// A photo at its own proportions, or at the proportions the layout asks for, filled and clipped. The rule colour shows while it loads.
struct BookImage: View {
    let photo: BookPhoto
    var aspect: CGFloat?
    var size: PhotoSizeVariant = .large
    var maxHeight: CGFloat?

    private var ratio: CGFloat {
        if let aspect { return aspect }
        guard photo.width > 0, photo.height > 0 else { return 4.0 / 3.0 }
        return CGFloat(photo.width) / CGFloat(photo.height)
    }

    var body: some View {
        BookPalette.rule
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: maxHeight)
            .overlay {
                RemotePhotoView(remoteId: photo.id, size: size)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photo.caption.isEmpty ? "Photo from \(BookDay.shortDay(photo.day))" : photo.caption)
            .accessibilityAddTraits(.isImage)
    }
}

/// The date under a photo or a moment, and how old the subject was — "May 4 · 2 months, 3 days".
struct BookWhen: View {
    let day: String
    let detail: String

    var body: some View {
        Text(detail.isEmpty ? BookDay.shortDay(day) : "\(BookDay.shortDay(day)) · \(detail)")
            .font(BookType.when)
            .foregroundStyle(BookPalette.inkSoft)
    }
}

struct BookFigure: View {
    let photo: BookPhoto
    var aspect: CGFloat?
    var size: PhotoSizeVariant = .medium
    var maxHeight: CGFloat? = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookImage(photo: photo, aspect: aspect, size: size, maxHeight: maxHeight)
            Caption(photo: photo)
        }
    }

    /// The caption in italic and the date beside it, or under it when there is no room.
    struct Caption: View {
        let photo: BookPhoto

        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    caption
                    Spacer(minLength: 12)
                    BookWhen(day: photo.day, detail: photo.detail)
                }
                VStack(alignment: .leading, spacing: 2) {
                    caption
                    BookWhen(day: photo.day, detail: photo.detail)
                }
            }
        }

        @ViewBuilder
        private var caption: some View {
            if !photo.caption.isEmpty {
                Text(photo.caption)
                    .font(BookType.serif(.subheadline).italic())
                    .foregroundStyle(BookPalette.ink)
            }
        }
    }
}

// MARK: - Blocks

/// One of the book's designed layouts. `index` is the block's place in its chapter, so a moment with a photo can alternate sides on a wide screen.
struct BookBlockView: View {
    let block: BookBlock
    let index: Int
    let axis: GrowthAxis
    /// The column's side margin, which a hero photo bleeds into.
    let gutter: CGFloat

    var body: some View {
        switch block {
        case .hero(let photo):
            // Wider than the column, nearly to the screen's edges, as `.book-hero` breaks out of the web's.
            VStack(alignment: .leading, spacing: 8) {
                BookImage(photo: photo, aspect: 3.0 / 2.0, size: .large)
                    .padding(.horizontal, -max(gutter - 8, 0))
                BookFigure.Caption(photo: photo)
            }
        case .photos(let photos):
            PhotoGroupView(photos: photos)
        case .moment(let moment, let photo):
            MomentView(moment: moment, photo: photo, photoTrailing: index.isMultiple(of: 2))
        case .quote(let moment):
            QuoteView(moment: moment)
        case .artwork(let moment, let photo):
            ArtworkView(moment: moment, photo: photo)
        case .notes(let moments):
            NotesView(moments: moments)
        case .facts(let lines):
            VStack(spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(BookType.serif(.body).smallCaps())
                        .tracking(0.6)
                }
            }
            .foregroundStyle(BookPalette.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .letter(let text, let signature):
            LetterView(text: text, signature: signature)
        case .growth(let height, let weight):
            GrowthBlockView(height: height, weight: weight, axis: axis)
        }
    }
}

/// One to four photos: one sits narrower and centred, three lead with a wide one, the rest pair up in portrait frames.
private struct PhotoGroupView: View {
    let photos: [BookPhoto]

    var body: some View {
        switch photos.count {
        case 1:
            BookFigure(photo: photos[0])
                .frame(maxWidth: 440)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
        case 3:
            VStack(spacing: 12) {
                BookFigure(photo: photos[0])
                pairs(Array(photos.dropFirst()))
            }
        default:
            pairs(photos)
        }
    }

    private func pairs(_ photos: [BookPhoto]) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 16) {
            ForEach(Array(stride(from: 0, to: photos.count, by: 2)), id: \.self) { start in
                GridRow(alignment: .top) {
                    BookFigure(photo: photos[start], aspect: 4.0 / 5.0)
                    if start + 1 < photos.count {
                        BookFigure(photo: photos[start + 1], aspect: 4.0 / 5.0)
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }
}

private struct MomentView: View {
    let moment: BookMoment
    let photo: BookPhoto?
    let photoTrailing: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if let photo {
            if sizeClass == .regular {
                HStack(alignment: .center, spacing: 24) {
                    if photoTrailing {
                        words
                        image(photo)
                    } else {
                        image(photo)
                        words
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    image(photo)
                    words
                }
            }
        } else {
            words
                .padding(.vertical, 8)
                .padding(.leading, 22)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(BookPalette.rule)
                        .frame(width: 3)
                }
        }
    }

    private func image(_ photo: BookPhoto) -> some View {
        BookImage(photo: photo, size: .medium, maxHeight: 520)
            .frame(maxWidth: .infinity)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 8) {
            if moment.first {
                Text("A first")
                    .font(BookType.label)
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(BookPalette.inkSoft)
            }
            Text(moment.text)
                .font(BookType.serif(.title3))
                .lineSpacing(4)
                .foregroundStyle(BookPalette.ink)
            if !moment.context.isEmpty {
                Text(moment.context)
                    .font(BookType.serif(.body))
                    .foregroundStyle(BookPalette.inkSoft)
            }
            BookWhen(day: moment.day, detail: moment.detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuoteView: View {
    let moment: BookMoment

    var body: some View {
        VStack(spacing: 12) {
            Text("\u{201C}\(moment.text)\u{201D}")
                .font(BookType.serif(.largeTitle).italic())
                .foregroundStyle(BookPalette.ink)
            if !moment.context.isEmpty {
                Text(moment.context)
                    .font(BookType.serif(.body))
                    .foregroundStyle(BookPalette.inkSoft)
                    .frame(maxWidth: 460)
            }
            BookWhen(day: moment.day, detail: moment.detail)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// A child's drawing, matted and hung: the whole picture, never cropped.
private struct ArtworkView: View {
    let moment: BookMoment
    let photo: BookPhoto

    var body: some View {
        VStack(spacing: 16) {
            RemotePhotoView(remoteId: photo.id, size: .large, contentMode: .fit)
                .aspectRatio(photo.width > 0 && photo.height > 0 ? CGFloat(photo.width) / CGFloat(photo.height) : 4.0 / 3.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(moment.text)
                .padding(22)
                .background(BookPalette.mat)
                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                .shadow(color: Color(red: 0.16, green: 0.12, blue: 0.08).opacity(0.14), radius: 15, y: 10)
            VStack(spacing: 4) {
                Text(moment.text)
                    .font(BookType.serif(.body).weight(.semibold))
                    .foregroundStyle(BookPalette.ink)
                if !moment.context.isEmpty {
                    Text(moment.context)
                        .font(BookType.serif(.body))
                        .foregroundStyle(BookPalette.inkSoft)
                }
                BookWhen(day: moment.day, detail: moment.detail)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

/// Small records gathered into a list, the date in a margin column on a wide screen and above the words on a phone.
private struct NotesView: View {
    let moments: [BookMoment]

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(moments.enumerated()), id: \.offset) { _, moment in
                if sizeClass == .regular {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        BookWhen(day: moment.day, detail: moment.detail)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 150, alignment: .trailing)
                        text(moment)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        BookWhen(day: moment.day, detail: moment.detail)
                        text(moment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func text(_ moment: BookMoment) -> some View {
        Text(moment.text)
            .font(BookType.serif(.body))
            .foregroundStyle(BookPalette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LetterView: View {
    let text: String
    let signature: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text)
                .font(BookType.serif(.title3).italic())
                .lineSpacing(5)
                .foregroundStyle(BookPalette.ink)
            if !signature.isEmpty {
                Text(signature)
                    .font(BookType.serif(.title3).italic())
                    .foregroundStyle(BookPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Growth

private struct GrowthBlockView: View {
    let height: [GrowthPoint]
    let weight: [GrowthPoint]
    let axis: GrowthAxis

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let layout = sizeClass == .regular
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
            : AnyLayout(VStackLayout(spacing: 28))
        layout {
            if !weight.isEmpty {
                BookGrowthChart(label: "Weight", points: weight, color: MeasurementType.weight.color, axis: axis)
            }
            if !height.isEmpty {
                BookGrowthChart(label: "Length", points: height, color: MeasurementType.height.color, axis: axis)
            }
        }
    }
}

/// A quiet line through the actual measurements, labelled at its two ends. Nothing is extrapolated: the line stops where the records do.
private struct BookGrowthChart: View {
    let label: String
    let points: [GrowthPoint]
    let color: Color
    let axis: GrowthAxis

    private var first: GrowthPoint { points[0] }
    private var last: GrowthPoint { points[points.count - 1] }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.15, 0.5)
        return (low - pad)...(high + pad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { offset, point in
                    LineMark(x: .value("Months", min(point.position, axis.span)), y: .value(label, point.value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(color)
                    PointMark(x: .value("Months", min(point.position, axis.span)), y: .value(label, point.value))
                        .symbolSize(36)
                        .foregroundStyle(color)
                        .annotation(position: offset == points.count - 1 ? .top : .trailing, alignment: offset == points.count - 1 ? .trailing : .leading, spacing: 6) {
                            if offset == 0 || offset == points.count - 1 {
                                Text(point.label)
                                    .font(.caption2)
                                    .foregroundStyle(BookPalette.ink)
                            }
                        }
                }
            }
            .chartXScale(domain: 0...axis.span)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: [0.0]) { _ in
                    AxisGridLine().foregroundStyle(BookPalette.rule)
                }
            }
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.overlay(alignment: .bottom) {
                    Rectangle().fill(BookPalette.rule).frame(height: 1)
                }
            }
            .frame(height: 150)

            HStack {
                Text(axis.start)
                Spacer()
                Text(axis.end)
            }
            .font(.caption2)
            .foregroundStyle(BookPalette.inkSoft)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: 12)
                    span
                }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    span
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(first.label) on \(BookDay.shortDay(first.day)), \(last.label) on \(BookDay.shortDay(last.day)), from \(points.count) measurements.")
    }

    private var title: some View {
        Text(label)
            .font(BookType.serif(.subheadline).weight(.semibold))
            .foregroundStyle(BookPalette.ink)
    }

    private var span: some View {
        Text("\(first.label) on \(BookDay.shortDay(first.day)) → \(last.label) on \(BookDay.shortDay(last.day))")
            .font(BookType.serif(.subheadline))
            .foregroundStyle(BookPalette.inkSoft)
    }
}
