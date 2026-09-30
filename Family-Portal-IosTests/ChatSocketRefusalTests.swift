import Testing
@testable import Family_Portal_Ios

@Suite("Chat socket refusals")
struct ChatSocketRefusalTests {

    @Test("A forbidden or missing chat endpoint is not retried")
    func permanentRefusals() {
        #expect(ChatWebSocketService.isPermanentRefusal(403))
        #expect(ChatWebSocketService.isPermanentRefusal(404))
    }

    @Test("An expired token and a server hiccup are retried")
    func transientRefusals() {
        #expect(!ChatWebSocketService.isPermanentRefusal(401))
        #expect(!ChatWebSocketService.isPermanentRefusal(502))
    }
}
