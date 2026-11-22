import SwiftUI
import UIKit

/// Turns a share card into the file the share sheet sends: a PNG sized for a phone message, or a letter-size PDF.
enum ShareRendering {
    static let imageWidth: CGFloat = 390
    /// Past this the recap goes out as a PDF rather than an image too tall to read in a message.
    static let maxImageHeight: CGFloat = 1100
    static let pageSize = CGSize(width: 612, height: 792)
    static let pageMargin: CGFloat = 40
    static let blockSpacing: CGFloat = 16

    static var pageContentSize: CGSize {
        CGSize(width: pageSize.width - pageMargin * 2, height: pageSize.height - pageMargin * 2)
    }

    enum Failure: LocalizedError {
        case render
        var errorDescription: String? { Copy.share.renderFailed }
    }

    static func prepared(_ view: some View, width: CGFloat) -> some View {
        view
            .frame(width: width, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
    }

    static func height(of view: some View, width: CGFloat) -> CGFloat {
        var measured = CGSize.zero
        ImageRenderer(content: prepared(view, width: width)).render { size, _ in measured = size }
        return measured.height
    }

    static func png(_ view: some View, width: CGFloat = imageWidth, named name: String) throws -> URL {
        let renderer = ImageRenderer(content: prepared(view, width: width))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { throw Failure.render }
        let url = try fileURL(name, extension: "png")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Each page is drawn whole, top-aligned inside the margins.
    static func pdf(pages: [AnyView], named name: String) throws -> URL {
        let url = try fileURL(name, extension: "pdf")
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw Failure.render }
        for page in pages {
            let content = page
                .frame(width: pageContentSize.width, height: pageContentSize.height, alignment: .topLeading)
                .padding(pageMargin)
                .background(Color.white)
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(pageSize)
            context.beginPDFPage(nil)
            renderer.render { _, draw in draw(context) }
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    /// A block taller than a page is shrunk to fit it, so nothing included is cut off.
    static func fitted(_ block: some View, height: CGFloat) -> AnyView {
        let available = pageContentSize
        guard height > available.height else {
            return AnyView(block.frame(width: available.width, alignment: .topLeading))
        }
        let scale = available.height / height
        return AnyView(
            block
                .frame(width: available.width, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: available.width, height: available.height, alignment: .topLeading)
        )
    }

    private static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
    }

    /// Files from earlier previews; the share sheet has finished with them by the time a new preview opens.
    static func clearOldFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func fileURL(_ name: String, extension ext: String) throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folder.appendingPathComponent(cleaned.isEmpty ? "Share" : cleaned).appendingPathExtension(ext)
    }
}

/// The bottom bar of a share preview: copy the text, or send the file.
struct ShareActionsBar: View {
    let text: String
    let file: URL?
    let fileLabel: String
    let isEnabled: Bool

    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                UIPasteboard.general.string = text
                copied = true
            } label: {
                Label(copied ? Copy.share.copied : Copy.share.copyText, systemImage: copied ? "checkmark" : "doc.on.doc")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .disabled(!isEnabled)

            Group {
                if let file {
                    ShareLink(item: file) {
                        Label(fileLabel, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Button {} label: {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled || file == nil)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
        .onChange(of: text) { copied = false }
    }
}
