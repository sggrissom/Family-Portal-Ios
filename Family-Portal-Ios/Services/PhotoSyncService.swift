import Foundation

enum PhotoSizeVariant: String {
    case small, thumb, medium, large, xlarge
}

actor PhotoSyncService {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func photoURL(remoteId: Int, size: PhotoSizeVariant) async -> URL? {
        let baseURL = await apiClient.getBaseURL()
        return baseURL.appendingPathComponent("api/photo/\(remoteId)/\(size.rawValue)")
    }

    func uploadPhoto(imageData: Data, title: String, description: String, photoDate: Date, personIds: [Int]) async throws -> ImageDTO {
        let boundary = "Boundary-\(UUID().uuidString)"
        let formData = buildMultipartBody(
            imageData: imageData,
            title: title,
            description: description,
            photoDate: photoDate,
            personIds: personIds,
            boundary: boundary
        )
        return try await apiClient.uploadMultipart(path: "api/photo/upload", formData: formData, boundary: boundary)
    }

    private func buildMultipartBody(imageData: Data, title: String, description: String, photoDate: Date, personIds: [Int], boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"

        // File part
        body.append("--\(boundary)\(crlf)")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\(crlf)")
        body.append("Content-Type: \(mimeType(for: imageData))\(crlf)\(crlf)")
        body.append(imageData)
        body.append(crlf)

        // Text fields
        appendTextField(to: &body, name: "title", value: title, boundary: boundary)
        appendTextField(to: &body, name: "description", value: description, boundary: boundary)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        appendTextField(to: &body, name: "photoDate", value: formatter.string(from: photoDate), boundary: boundary)

        if let personIdsJSON = try? JSONSerialization.data(withJSONObject: personIds),
           let personIdsString = String(data: personIdsJSON, encoding: .utf8) {
            appendTextField(to: &body, name: "personIds", value: personIdsString, boundary: boundary)
        }

        // Closing boundary
        body.append("--\(boundary)--\(crlf)")

        return body
    }

    private func appendTextField(to body: inout Data, name: String, value: String, boundary: String) {
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
        body.append("\(value)\(crlf)")
    }

    private func mimeType(for data: Data) -> String {
        var header = [UInt8](repeating: 0, count: 8)
        data.copyBytes(to: &header, count: min(8, data.count))

        if header[0] == 0xFF && header[1] == 0xD8 {
            return "image/jpeg"
        } else if header[0] == 0x89 && header[1] == 0x50 {
            return "image/png"
        } else if header[0] == 0x47 && header[1] == 0x49 {
            return "image/gif"
        } else if header[0] == 0x52 && header[1] == 0x49 {
            return "image/webp"
        }
        return "image/jpeg"
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
