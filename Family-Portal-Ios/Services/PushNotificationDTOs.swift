import Foundation

struct RegisterPushTokenRequestDTO: Encodable {
    let token: String
    let platform: String
    let environment: String
}

struct RegisterPushTokenResponseDTO: Decodable {
    let success: Bool
    let error: String?
}

struct UnregisterPushTokenRequestDTO: Encodable {
    let token: String
    let platform: String
    let environment: String
}

struct UnregisterPushTokenResponseDTO: Decodable {
    let success: Bool
    let error: String?
}

extension APIClient {
    func registerPushToken(token: String, environment: String) async throws -> Bool {
        let request = RegisterPushTokenRequestDTO(token: token, platform: "ios", environment: environment)
        let response: RegisterPushTokenResponseDTO = try await request(
            path: "api/notifications/push/register",
            method: .post,
            body: request,
            requiresAuth: true
        )
        return response.success
    }

    func unregisterPushToken(token: String, environment: String) async throws -> Bool {
        let request = UnregisterPushTokenRequestDTO(token: token, platform: "ios", environment: environment)
        let response: UnregisterPushTokenResponseDTO = try await request(
            path: "api/notifications/push/unregister",
            method: .post,
            body: request,
            requiresAuth: true
        )
        return response.success
    }
}
