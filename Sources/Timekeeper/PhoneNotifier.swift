import Foundation

/// Sends push notifications to the user's phone through ntfy.sh (the phone subscribes to the same topic in the ntfy app).
enum PhoneNotifier {
    enum Failure: LocalizedError {
        case invalidTopic, badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .invalidTopic: "Topic must be 1–64 letters, numbers, - or _"
            case .badStatus(let code): "ntfy answered with HTTP \(code)"
            }
        }
    }

    /// ntfy topics are public: anyone who knows the name can read it, so default to a long random one.
    static func randomTopic() -> String {
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return "timekeeper-" + String((0..<16).map { _ in chars.randomElement()! })
    }

    static func isValid(topic: String) -> Bool {
        !topic.isEmpty && topic.count <= 64 && topic.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func send(topic: String, title: String, message: String, tags: String) async throws {
        guard isValid(topic: topic), let url = URL(string: "https://ntfy.sh/\(topic)") else { throw Failure.invalidTopic }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(message.utf8)
        request.setValue(title, forHTTPHeaderField: "Title")  // keep ASCII; emoji go via tags
        request.setValue(tags, forHTTPHeaderField: "Tags")
        request.timeoutInterval = 15
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.badStatus(http.statusCode)
        }
    }
}
