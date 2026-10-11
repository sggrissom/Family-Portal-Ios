import AppIntents
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

/// A snapshot image, read from the App Group. It was downsampled by the app, so loading it whole stays inside the extension's memory limit.
struct SnapshotImage: View {
    let file: String?
    /// `.fit` for artwork, whose edges are part of the work.
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image = Self.load(file) {
            // Tinted rendering would otherwise draw a photo as a solid silhouette.
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .aspectRatio(contentMode: contentMode)
        } else {
            Rectangle().fill(.quaternary)
        }
    }

    static func load(_ file: String?) -> UIImage? {
        guard let file, let store = WidgetStore.shared() else { return nil }
        return UIImage(contentsOfFile: store.imageURL(file).path)
    }
}

/// Whether a snapshot image can be drawn: the file is there and decodes as an image. Checked once per file per timeline, so a missing or corrupt file chooses the words-only layout instead of an empty frame.
final class SnapshotImageCheck {
    private let store = WidgetStore.shared()
    private var known: [String: Bool] = [:]

    func isAvailable(_ file: String) -> Bool {
        if let answer = known[file] { return answer }
        var answer = false
        if let store, let source = CGImageSourceCreateWithURL(store.imageURL(file) as CFURL, nil) {
            answer = CGImageSourceGetStatus(source) == .statusComplete && CGImageSourceGetCount(source) > 0
        }
        known[file] = answer
        return answer
    }
}

/// A picture filling its frame: cropped, or for artwork fitted inside it.
struct FilledImage: View {
    let file: String?
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { proxy in
            SnapshotImage(file: file, contentMode: contentMode)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
    }
}

extension WidgetItem {
    /// Artwork is fitted rather than cropped: cropping a drawing cuts off the drawing.
    var imageContentMode: ContentMode { kind == .artwork ? .fit : .fill }
}

/// The SF Symbol for an item that has only words.
extension WidgetItem.Kind {
    var symbol: String {
        switch self {
        case .photo: "photo"
        case .milestone: "star.fill"
        case .quote: "text.bubble.fill"
        case .artwork: "paintpalette.fill"
        }
    }
}

/// The small context line every layout starts from: what kind of record and how it is dated.
struct ContextLabel: View {
    let text: String
    var symbol: String?

    var body: some View {
        Group {
            if let symbol {
                Label(text, systemImage: symbol)
            } else {
                Text(text)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tint)
        .widgetAccentable()
        .lineLimit(1)
    }
}

/// A record's words as the focal point, sized by how many there are, so a short milestone fills the card and a long one still fits. Quotes are italic, and the stored text already carries its quotation marks.
struct FeatureText: View {
    let text: String
    let kind: WidgetItem.Kind
    let room: Room

    enum Room { case small, medium, large }

    var body: some View {
        Text(text)
            .font(font)
            .italic(kind == .quote)
            .lineLimit(lineLimit)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var font: Font {
        let length = text.count
        switch room {
        case .small:
            return length <= 30 ? .title3.weight(.semibold) : length <= 70 ? .callout.weight(.medium) : .footnote
        case .medium:
            return length <= 40 ? .title2.weight(.semibold) : length <= 90 ? .title3.weight(.medium) : .callout
        case .large:
            return length <= 40 ? .largeTitle.weight(.semibold) : length <= 100 ? .title.weight(.medium) : length <= 180 ? .title3 : .body
        }
    }

    /// Past these the text ends in an ellipsis — the continuation cue — and the tap opens the whole record.
    private var lineLimit: Int {
        switch room {
        case .small: 5
        case .medium: 4
        case .large: 9
        }
    }
}

/// A quiet bottom row: the date or attribution, and room kept for Shuffle so it never sits on the words.
struct MomentFooter: View {
    let text: String
    var shuffles = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if shuffles {
                ShuffleButton()
            }
        }
    }
}

/// Moves the Memory widgets on by one without opening the app. The offset is shared, so every Memory widget moves.
struct ShuffleButton: View {
    var body: some View {
        Button(intent: ShuffleMemoryIntent()) {
            Image(systemName: "shuffle")
                .font(.caption.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .background(.fill.secondary, in: .circle)
        .foregroundStyle(.secondary)
        .accessibilityLabel(WidgetCopy.shuffle)
    }
}

/// Words laid over a photo: a scrim keeps them legible whatever the picture.
struct PhotoCaption: View {
    let title: String
    var detail: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !title.isEmpty {
                Text(title).font(.caption.weight(.semibold))
            }
            if !detail.isEmpty {
                Text(detail).font(.caption2)
            }
        }
        .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// The signed-out and empty states every size shares.
struct WidgetMessage: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .widgetAccentable()
            Spacer(minLength: 0)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
