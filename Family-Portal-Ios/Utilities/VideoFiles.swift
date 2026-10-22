import Foundation

/// What may be uploaded as a video, and why not: a port of frontend/lib/videoFiles.ts, worded the same, so a file refused on one client is refused in the same words on the other. The server checks all of it again; these are for saying so before a gigabyte has been sent.
nonisolated enum VideoFiles {
    /// The type the upload declares, from the file's extension — the only reliable thing a picked file carries. `nil` for anything the server won't take.
    static func contentType(forFilename filename: String) -> String? {
        switch (filename as NSString).pathExtension.lowercased() {
        case "mov": return "video/quicktime"
        case "mp4": return "video/mp4"
        case "m4v": return "video/x-m4v"
        default: return nil
        }
    }

    /// Why this file can't be added, or `nil` when it can. Duration is a separate check, since it needs the file read.
    static func problem(filename: String, size: Int, support: GetVideoSupportResponseDTO) -> String? {
        guard support.enabled else {
            return "\(filename): \(support.reason.isEmpty ? "videos can't be added here" : support.reason)"
        }
        guard contentType(forFilename: filename) != nil else {
            return "\(filename) is not an MP4 or MOV video"
        }
        if size > support.maxBytes {
            return "\(filename) is over \(formatBytes(support.maxBytes))"
        }
        return nil
    }

    /// With a second of slack, since a clip's reported length and the server's probe can disagree by a frame.
    static func durationProblem(filename: String, seconds: Double?, maxSeconds: Int) -> String? {
        guard let seconds, seconds.isFinite, seconds > Double(maxSeconds) + 1 else { return nil }
        let minutes = Int((Double(maxSeconds) / 60).rounded())
        return "\(filename) is \(VideoDuration.format(milliseconds: Int(seconds * 1000))) long; videos can be at most \(minutes) minutes"
    }

    /// The web's `formatBytes`: binary units, one decimal under ten.
    static func formatBytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var size = Double(bytes)
        var unit = 0
        while size >= 1024 && unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        let decimals = size >= 10 || unit == 0 ? 0 : 1
        return String(format: "%.\(decimals)f %@", size, units[unit])
    }
}
