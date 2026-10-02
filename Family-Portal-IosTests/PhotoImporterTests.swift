import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Family_Portal_Ios

@Suite("Photo import")
@MainActor
struct PhotoImporterTests {

    // MARK: - Progress accounting

    @Test("A run is finished only once every item has settled")
    func settledCountsBothOutcomes() {
        var progress = PhotoImporter.ImportProgress()
        progress.total = 3
        progress.completed = 1
        progress.failed = 1

        #expect(progress.settled == 2)
        #expect(!progress.isFinished)

        progress.failed = 2
        #expect(progress.settled == 3)
        #expect(progress.isFinished)
    }

    /// A batch where everything fails still has to finish, or the progress bar never comes down and the failures are never reported.
    @Test("A run where every item fails still finishes")
    func allFailuresStillFinish() {
        var progress = PhotoImporter.ImportProgress()
        progress.total = 2
        progress.failed = 2

        #expect(progress.isFinished)
    }

    /// A second pick made mid-import extends the run rather than starting a competing one, so `total` can grow past what has already settled.
    @Test("An extended run is unfinished again")
    func extendingAnInFlightRun() {
        var progress = PhotoImporter.ImportProgress()
        progress.total = 2
        progress.completed = 2
        #expect(progress.isFinished)

        progress.total += 3
        #expect(!progress.isFinished)
        #expect(progress.settled == 2)
    }

    @Test("An empty pick is not an import")
    func emptyPickStartsNothing() throws {
        let importer = PhotoImporter()
        importer.importPicked(
            [],
            into: try TestStore.makeContext(),
            syncService: nil,
            errorPresenter: nil
        )

        #expect(importer.progress == nil)
    }

    // MARK: - EXIF dates

    @Test("EXIF spells its dates with colons in the date, not only the time")
    func exifDateSpelling() {
        let parsed = PhotoImporter.exifDate(from: "2026:03:15 14:30:00")
        #expect(parsed != nil)

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: parsed!)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 15)
        #expect(components.hour == 14)
        #expect(components.minute == 30)
    }

    @Test("An ISO date is not an EXIF date")
    func isoIsNotExif() {
        #expect(PhotoImporter.exifDate(from: "2026-03-15T14:30:00Z") == nil)
        #expect(PhotoImporter.exifDate(from: "") == nil)
    }

    @Test("A photo's capture date is read out of its own EXIF")
    func captureDateFromEmbeddedExif() throws {
        let data = try Self.jpeg(exifDateTimeOriginal: "2026:03:15 14:30:00")
        let captured = try #require(PhotoImporter.captureDate(from: data))

        let components = Calendar.current.dateComponents([.year, .month, .day], from: captured)
        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 15)
    }

    /// The date falls back to "now" at the call site, so an image with no EXIF has to answer nil rather than an epoch — a photo dated 1970 sorts to the bottom of every gallery forever.
    @Test("A photo with no EXIF date has none, rather than a wrong one")
    func captureDateAbsent() throws {
        let data = try Self.jpeg(exifDateTimeOriginal: nil)
        #expect(PhotoImporter.captureDate(from: data) == nil)
    }

    @Test("Bytes that are not an image have no capture date")
    func captureDateFromGarbage() {
        #expect(PhotoImporter.captureDate(from: Data([0x00, 0x01, 0x02])) == nil)
    }

    /// A one-pixel JPEG, optionally carrying `DateTimeOriginal`. Built rather than checked in, so the test states exactly what it is asserting about.
    static func jpeg(exifDateTimeOriginal: String?) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let cgImage = try #require(image.cgImage)

        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        )

        var properties: [CFString: Any] = [:]
        if let exifDateTimeOriginal {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: exifDateTimeOriginal
            ] as CFDictionary
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        return output as Data
    }
}
