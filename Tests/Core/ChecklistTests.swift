import Foundation
import Testing

@testable import ChecklistCore

@Test func independentOfflineEditsConvergeAndSurviveRelaunch() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let phone = ChecklistStore(url: root.appendingPathComponent("phone.json"))
  let watch = ChecklistStore(url: root.appendingPathComponent("watch.json"))
  let initial = try await phone.add(title: "Check equipment", group: "Site visit")
  _ = try await watch.merge(initial.encoded())
  let id = initial.items[0].id
  let phoneEdit = try await phone.change(id, to: .completed(true))
  let watchEdit = try await watch.change(id, to: .archived(true))
  let a = try await phone.merge(watchEdit.encoded())
  let b = try await watch.merge(phoneEdit.encoded())
  #expect(a.items == b.items)
  let reopened = try await ChecklistStore(url: root.appendingPathComponent("phone.json")).load()
  #expect(reopened.items == a.items)
  let restored = try await phone.change(id, to: .archived(false))
  let synced = try await watch.merge(restored.encoded())
  #expect(!synced.items[0].archived)
  #expect(synced.items[0].stamp.counter > a.items[0].stamp.counter)
}

@Test func oldSnapshotsCannotResurrectArchivedItems() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = ChecklistStore(url: root.appendingPathComponent("state.json"))
  let initial = try await store.add(title: "Lock cabinet", group: "Closing")
  _ = try await store.change(initial.items[0].id, to: .archived(true))
  let merged = try await store.merge(initial.encoded())
  #expect(merged.items[0].archived)
}

@Test func invalidPacketLeavesPersistedStateUntouched() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let url = root.appendingPathComponent("state.json")
  let store = ChecklistStore(url: url)
  let initial = try await store.add(title: "Pack tools", group: "Morning")
  let bytes = try Data(contentsOf: url)
  var corrupt = initial
  corrupt.items[0].title = "Changed without a new edit stamp"
  await #expect(throws: ChecklistError.self) { try await store.merge(corrupt.encoded()) }
  #expect(try Data(contentsOf: url) == bytes)
  #expect(throws: ChecklistError.self) {
    try ChecklistEnvelope.decode(Data(repeating: 0, count: 250_001))
  }
}
