import CoreImage
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers
import Vision

/// "Lift from background" for a single drawing: Vision's subject lifting cuts the drawing out of the table or fridge it was photographed on, as Photos does. The result is a PNG, kept transparent, and is added beside the original rather than replacing it — a lift can clip a faint pencil line.
enum SubjectLift {

    /// The lifted subject, cropped to it, or nil when Vision finds nothing to lift (or can't run, as on a simulator).
    nonisolated static func lift(_ data: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            liftNow(data)
        }.value
    }

    private nonisolated static func liftNow(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? UInt32

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(
            cgImage: image,
            orientation: orientation.flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        )
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciImage = CIImage(cvPixelBuffer: masked)
            let context = CIContext()
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return context.pngRepresentation(of: ciImage, format: .RGBA8, colorSpace: colorSpace)
        } catch {
            Logger(subsystem: "com.familyrecord.ios", category: "ui").error("Subject lift failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
