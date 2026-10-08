import Foundation

public struct Snapshot: Codable, Equatable, Sendable {
    public var tracker: Tracker
    /// Heartbeat: last moment the app was known alive; used to close open entries after a crash.
    public var lastSeen: Date

    public init(tracker: Tracker, lastSeen: Date) {
        self.tracker = tracker
        self.lastSeen = lastSeen
    }
}

public struct Store: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Timekeeper", isDirectory: true)
            .appendingPathComponent("data.json")
    }

    /// Returns nil when no data file exists yet.
    public func load() throws -> Snapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
    }

    public func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    /// Moves an unreadable data file aside so a fresh save never overwrites it.
    public func backUpCorruptFile() {
        let backup = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: url, to: backup)
    }
}
