import Foundation
import Testing
@testable import TimekeeperCore

struct StoreTests {
    let store = Store(url: FileManager.default.temporaryDirectory
        .appendingPathComponent("timekeeper-tests-\(UUID().uuidString)")
        .appendingPathComponent("data.json"))

    @Test func missingFileLoadsAsNil() throws {
        #expect(try store.load() == nil)
    }

    @Test func roundTripPreservesStateIncludingOpenEntry() throws {
        var t = Tracker()
        let a = t.addActivity(name: "Deep work")
        t.start(a, now: at(0), breakLength: 600)
        let snapshot = Snapshot(tracker: t, lastSeen: at(42))

        try store.save(snapshot)
        let loaded = try #require(try store.load())
        #expect(loaded == snapshot)

        var recovered = loaded.tracker
        recovered.recover(lastSeen: loaded.lastSeen)
        #expect(recovered.total(kind: .work, in: everything, now: at(9999)) == 42)
    }
}
