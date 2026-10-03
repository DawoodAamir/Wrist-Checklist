import Foundation

struct ChecklistGlance: Codable, Sendable {
  let remaining: Int
  let title: String?
  let updated: Date
  static let empty = ChecklistGlance(remaining: 0, title: nil, updated: .distantPast)
}
enum ChecklistLocation {
  static let group = "group.com.dd.wristchecklist"
  static var container: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
  }
  static var glanceURL: URL? { container?.appendingPathComponent("Glance.json") }
  static func readGlance() -> ChecklistGlance {
    guard let url = glanceURL, let data = try? Data(contentsOf: url), data.count < 10_000,
      let result = try? JSONDecoder().decode(ChecklistGlance.self, from: data),
      (0...200).contains(result.remaining), (result.title?.count ?? 0) <= 160
    else { return .empty }
    return result
  }
}
