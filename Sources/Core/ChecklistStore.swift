import Foundation

struct EditStamp: Codable, Sendable, Equatable, Comparable {
  let counter: UInt64
  let author: UUID
  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.counter == rhs.counter
      ? lhs.author.uuidString < rhs.author.uuidString : lhs.counter < rhs.counter
  }
}
struct ChecklistItem: Codable, Sendable, Equatable, Identifiable {
  let id: UUID
  var title: String
  var group: String
  var completed: Bool
  var archived: Bool
  var reminder: Date?
  var stamp: EditStamp
}
struct ChecklistEnvelope: Codable, Sendable {
  var format = 1
  var items: [ChecklistItem]
  func validated() throws -> Self {
    guard format == 1, items.count <= 200, Set(items.map(\.id)).count == items.count else {
      throw ChecklistError.invalid
    }
    for item in items {
      guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        item.title.count <= 160, item.group.count <= 60,
        item.stamp.counter > 0, item.stamp.counter < 1_000_000_000_000
      else { throw ChecklistError.invalid }
      if let date = item.reminder {
        guard date.timeIntervalSince1970.isFinite,
          (0...4_102_444_800).contains(date.timeIntervalSince1970)
        else { throw ChecklistError.invalid }
      }
    }
    return self
  }
  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(validated())
    guard data.count <= 250_000 else { throw ChecklistError.invalid }
    return data
  }
  static func decode(_ data: Data) throws -> Self {
    guard data.count <= 250_000 else { throw ChecklistError.invalid }
    return try JSONDecoder().decode(Self.self, from: data).validated()
  }
}
enum ChecklistError: LocalizedError {
  case invalid, limit, missing, ambiguous
  var errorDescription: String? {
    switch self {
    case .invalid: "The checklist data is invalid or exceeds its supported limits."
    case .limit: "This workspace holds 200 items, including archived items."
    case .missing: "This item is no longer available."
    case .ambiguous:
      "Conflicting data has the same edit identifier. The incoming update was not applied."
    }
  }
}

actor ChecklistStore {
  private struct State: Codable {
    var device: UUID
    var clock: UInt64
    var envelope: ChecklistEnvelope
  }
  private let url: URL
  private var state: State?
  init(url: URL) { self.url = url }
  func load() throws -> ChecklistEnvelope {
    if let state { return state.envelope }
    if FileManager.default.fileExists(atPath: url.path) {
      let data = try Data(contentsOf: url)
      guard data.count <= 260_000 else { throw ChecklistError.invalid }
      let saved = try JSONDecoder().decode(State.self, from: data)
      _ = try saved.envelope.validated()
      guard saved.clock < 1_000_000_000_000,
        saved.clock >= (saved.envelope.items.map(\.stamp.counter).max() ?? 0)
      else { throw ChecklistError.invalid }
      state = saved
    } else {
      state = State(device: UUID(), clock: 0, envelope: ChecklistEnvelope(items: []))
    }
    return state!.envelope
  }
  func add(title: String, group: String) throws -> ChecklistEnvelope {
    _ = try load()
    var next = state!
    guard next.envelope.items.count < 200 else { throw ChecklistError.limit }
    next.clock += 1
    next.envelope.items.append(
      ChecklistItem(
        id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines),
        group: group.trimmingCharacters(in: .whitespacesAndNewlines), completed: false,
        archived: false, reminder: nil, stamp: EditStamp(counter: next.clock, author: next.device)))
    return try commit(next)
  }
  enum Change: Sendable {
    case completed(Bool)
    case archived(Bool)
    case reminder(Date?)
    case rename(String, String)
  }
  func change(_ id: UUID, to change: Change) throws -> ChecklistEnvelope {
    _ = try load()
    var next = state!
    guard let index = next.envelope.items.firstIndex(where: { $0.id == id }) else {
      throw ChecklistError.missing
    }
    switch change {
    case .completed(let value): next.envelope.items[index].completed = value
    case .archived(let value): next.envelope.items[index].archived = value
    case .reminder(let value): next.envelope.items[index].reminder = value
    case .rename(let title, let group):
      next.envelope.items[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
      next.envelope.items[index].group = group.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    next.clock += 1
    next.envelope.items[index].stamp = EditStamp(counter: next.clock, author: next.device)
    return try commit(next)
  }
  func merge(_ incoming: Data) throws -> ChecklistEnvelope {
    let envelope = try ChecklistEnvelope.decode(incoming)
    _ = try load()
    var next = state!
    var items = Dictionary(uniqueKeysWithValues: next.envelope.items.map { ($0.id, $0) })
    for record in envelope.items {
      if let existing = items[record.id] {
        if existing.stamp == record.stamp && existing != record { throw ChecklistError.ambiguous }
        if existing.stamp < record.stamp { items[record.id] = record }
      } else {
        items[record.id] = record
      }
      next.clock = max(next.clock, record.stamp.counter)
    }
    next.envelope.items = items.values.sorted { $0.id.uuidString < $1.id.uuidString }
    return try commit(next)
  }
  private func commit(_ next: State) throws -> ChecklistEnvelope {
    _ = try next.envelope.encoded()
    let data = try JSONEncoder().encode(next)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    state = next
    return next.envelope
  }
}
