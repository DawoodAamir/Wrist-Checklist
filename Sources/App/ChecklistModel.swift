import Foundation
import Observation
import UserNotifications
@preconcurrency import WatchConnectivity
import WidgetKit

@MainActor @Observable final class ChecklistModel: NSObject {
  private(set) var items: [ChecklistItem] = []
  private(set) var loaded = false
  private(set) var syncing = "Changes are saved on this device."
  private(set) var pending = 0
  var error: String?
  private let store: ChecklistStore
  private let testMode: Bool
  private var queue: Task<Void, Never>?
  private var latestPayload: Data?
  private var lastSent: Data?
  private var connection: WCSession?
  override init() {
    var directory = URL.applicationSupportDirectory.appendingPathComponent(
      "WristChecklist", isDirectory: true)
    #if DEBUG
      if let test = ProcessInfo.processInfo.environment["CHECKLIST_TEST_STORE"],
        UUID(uuidString: test) != nil
      {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(test)
        testMode = true
      } else {
        testMode = false
      }
    #else
      testMode = false
    #endif
    store = ChecklistStore(url: directory.appendingPathComponent("Checklist.json"))
    super.init()
  }
  func load() {
    guard !loaded else { return }
    loaded = true
    enqueue { try await $0.load() }
    if !testMode, WCSession.isSupported() {
      connection = .default
      connection?.delegate = self
      connection?.activate()
    }
  }
  func add(title: String, group: String) {
    enqueue { try await $0.add(title: title, group: group) }
  }
  func change(_ id: UUID, to change: ChecklistStore.Change) {
    enqueue { try await $0.change(id, to: change) }
  }
  func retrySync() {
    lastSent = nil
    publish()
  }
  private func enqueue(
    _ work: @escaping @Sendable (ChecklistStore) async throws -> ChecklistEnvelope
  ) {
    let previous = queue
    pending += 1
    queue = Task { [weak self] in
      await previous?.value
      guard let self else { return }
      defer { self.pending -= 1 }
      do {
        let result = try await work(self.store)
        self.items = result.items.sorted {
          if $0.group != $1.group { return $0.group < $1.group }
          if $0.title != $1.title { return $0.title < $1.title }
          return $0.id.uuidString < $1.id.uuidString
        }
        self.latestPayload = try ChecklistEnvelope(
          items: result.items.sorted { $0.id.uuidString < $1.id.uuidString }
        ).encoded()
        if !self.testMode {
          self.writeGlance()
          await self.reconcileReminders()
          self.publish()
        }
      } catch { self.error = error.localizedDescription }
    }
  }
  private func writeGlance() {
    let open = items.filter { !$0.completed && !$0.archived }
    guard let url = ChecklistLocation.glanceURL else { return }
    do {
      let value = ChecklistGlance(remaining: open.count, title: open.first?.title, updated: Date())
      try JSONEncoder().encode(value).write(to: url, options: .atomic)
      WidgetCenter.shared.reloadAllTimelines()
    } catch { self.error = "The checklist was saved, but its complication could not refresh." }
  }
  func requestReminder(_ id: UUID, at date: Date) async {
    #if os(iOS)
      do {
        guard
          try await UNUserNotificationCenter.current().requestAuthorization(options: [
            .alert, .sound,
          ])
        else {
          error = "Enable notifications in Settings to receive checklist reminders."
          return
        }
        change(id, to: .reminder(date))
      } catch { self.error = error.localizedDescription }
    #endif
  }
  private func reconcileReminders() async {
    #if os(iOS)
      let center = UNUserNotificationCenter.current()
      let desired = Array(
        items.filter { !$0.completed && !$0.archived && ($0.reminder ?? .distantPast) > Date() }
          .sorted { ($0.reminder ?? .distantFuture) < ($1.reminder ?? .distantFuture) }.prefix(60))
      let desiredIDs = Set(desired.map { "checklist." + $0.id.uuidString })
      let existing = await center.pendingNotificationRequests().filter {
        $0.identifier.hasPrefix("checklist.")
      }
      center.removePendingNotificationRequests(
        withIdentifiers: existing.map(\.identifier).filter { !desiredIDs.contains($0) })
      for item in desired.prefix(60) {
        guard let reminder = item.reminder else { continue }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.group.isEmpty ? "Checklist reminder" : item.group
        content.sound = .default
        let request = UNNotificationRequest(
          identifier: "checklist." + item.id.uuidString, content: content,
          trigger: UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, reminder.timeIntervalSinceNow), repeats: false))
        do { try await center.add(request) } catch {
          self.error = "The checklist was saved, but a reminder could not be scheduled."
        }
      }
    #endif
  }
  private func publish() {
    guard let connection, connection.activationState == .activated, let latestPayload else {
      return
    }
    #if os(iOS)
      guard connection.isPaired, connection.isWatchAppInstalled else {
        syncing = "Install Wrist Checklist on your paired Apple Watch to sync."
        return
      }
    #else
      guard connection.isCompanionAppInstalled else {
        syncing = "Install Wrist Checklist on your paired iPhone to sync."
        return
      }
    #endif
    guard latestPayload != lastSent else { return }
    do {
      try connection.updateApplicationContext(["checklist": latestPayload])
      lastSent = latestPayload
      syncing = "Latest checklist queued for your paired device. Delivery is managed by watchOS."
    } catch { syncing = "Saved locally. Sync will retry when the paired device is available." }
  }
  private func receive(_ data: Data) { enqueue { try await $0.merge(data) } }
}
extension ChecklistModel: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let received = session.receivedApplicationContext["checklist"] as? Data
    let message = error?.localizedDescription
    Task { @MainActor [weak self] in
      guard let self else { return }
      if let message { self.syncing = "Saved locally. \(message)" }
      if let received { self.receive(received) }
      self.publish()
    }
  }
  nonisolated func session(
    _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    guard let data = applicationContext["checklist"] as? Data else { return }
    Task { @MainActor [weak self] in self?.receive(data) }
  }
  #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
      Task { @MainActor [weak self] in
        self?.lastSent = nil
        self?.connection?.activate()
      }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
      Task { @MainActor [weak self] in
        self?.lastSent = nil
        self?.publish()
      }
    }
  #endif
}
