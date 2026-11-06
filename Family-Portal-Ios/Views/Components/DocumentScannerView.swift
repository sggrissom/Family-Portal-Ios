import OSLog
import SwiftUI
import UIKit
import VisionKit

/// VisionKit's document camera: finds the page's edges, flattens it and lets the user take several in a row. For drawings, report cards and certificates, which a plain photo gets at an angle.
/// Hands back each page as JPEG, or an empty array when the user cancels. Check `isAvailable` first — a simulator has no document camera.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onFinish: ([Data]) -> Void

    static var isAvailable: Bool {
        VNDocumentCameraViewController.isSupported
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([Data]) -> Void

        init(onFinish: @escaping ([Data]) -> Void) {
            self.onFinish = onFinish
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            // One page decoded at a time: a stack of full-resolution scans held at once is the memory spike the importer avoids too.
            let pages = (0..<scan.pageCount).compactMap { index in
                autoreleasepool { scan.imageOfPage(at: index).jpegData(compressionQuality: 0.9) }
            }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            AppLog.ui.error("Document camera failed: \(String(describing: error), privacy: .public)")
            onFinish([])
        }
    }
}
