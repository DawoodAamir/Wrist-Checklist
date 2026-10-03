import AppIntents
import SwiftUI

@main struct WristChecklistApp: App {
  @State private var model = ChecklistModel()
  var body: some Scene { WindowGroup { ChecklistView(model: model) } }
}
struct OpenChecklistIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Wrist Checklist"
  static let description = IntentDescription(
    "Open your offline checklist and its next unfinished item.")
  static let openAppWhenRun = true
  func perform() async throws -> some IntentResult { .result() }
}
struct ChecklistShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: OpenChecklistIntent(), phrases: ["Open my checklist in \(.applicationName)"],
      shortTitle: "Open checklist", systemImageName: "checklist")
  }
}
struct ChecklistView: View {
  @Bindable var model: ChecklistModel
  @State private var adding = false
  @State private var archived = false
  var visible: [ChecklistItem] { model.items.filter { $0.archived == archived } }
  var groups: [String] { Array(Set(visible.map(\.group))).sorted() }
  var body: some View {
    NavigationStack {
      List {
        if !archived {
          Section {
            VStack(alignment: .leading, spacing: 5) {
              Text("\(visible.filter { !$0.completed }.count) remaining").font(.title2.bold())
              Text("\(visible.filter(\.completed).count) completed").font(.caption).foregroundStyle(
                .secondary)
            }.accessibilityElement(children: .combine)
          }
        }
        Section {
          Button("Add task", systemImage: "plus") { adding = true }.accessibilityIdentifier(
            "addTask")
        }
        if visible.isEmpty {
          ContentUnavailableView(
            archived ? "No archived items" : "A clear checklist", systemImage: "checklist",
            description: Text(
              archived
                ? "Archived items remain recoverable."
                : "Add your first task for a site visit, shift, or daily routine."))
        }
        ForEach(groups, id: \.self) { group in
          Section(group.isEmpty ? "Tasks" : group) {
            ForEach(visible.filter { $0.group == group }) { item in
              HStack {
                Button {
                  model.change(item.id, to: .completed(!item.completed))
                } label: {
                  Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(item.completed ? .teal : .secondary)
                }.buttonStyle(.borderless).accessibilityLabel(
                  item.completed ? "Mark incomplete: \(item.title)" : "Complete: \(item.title)"
                )
                .disabled(archived || model.pending > 0)
                NavigationLink {
                  ItemDetail(itemID: item.id, model: model)
                } label: {
                  Text(item.title).strikethrough(item.completed).foregroundStyle(
                    item.completed ? .secondary : .primary)
                }
              }
            }
          }
        }
        Section {
          Toggle("Show archived", isOn: $archived)
          Text(model.syncing).font(.footnote).foregroundStyle(.secondary)
          Button("Retry sync") { model.retrySync() }
        }
      }.navigationTitle("Checklist").task { model.load() }
        .sheet(isPresented: $adding) { AddTaskView(model: model) }
        .alert(
          "Unable to update checklist",
          isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
        ) {
          Button("OK") { model.error = nil }
        } message: {
          Text(model.error ?? "")
        }
    }.tint(.teal)
  }
}
struct AddTaskView: View {
  let model: ChecklistModel
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var group = ""
  var body: some View {
    NavigationStack {
      Form {
        TextField("Task", text: $title).accessibilityIdentifier("taskTitle")
        TextField("Group (optional)", text: $group).accessibilityIdentifier("taskGroup")
        Text("Use the system keyboard or dictation to enter a task.").font(.footnote)
          .foregroundStyle(.secondary)
        Button("Add") {
          model.add(title: title, group: group)
          dismiss()
        }
        .disabled(
          title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 160
            || group.count > 60 || model.pending > 0)
      }.navigationTitle("New task")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
  }
}
struct ItemDetail: View {
  let itemID: UUID
  @Bindable var model: ChecklistModel
  @State private var title = ""
  @State private var group = ""
  @State private var date = Date().addingTimeInterval(3600)
  var item: ChecklistItem? { model.items.first { $0.id == itemID } }
  var body: some View {
    Form {
      if let item {
        Section("Task") {
          TextField("Task", text: $title)
          TextField("Group", text: $group)
          Button("Save changes") { model.change(itemID, to: .rename(title, group)) }
            .disabled(
              title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 160
                || group.count > 60 || model.pending > 0)
        }
        Section {
          Button(item.completed ? "Mark incomplete" : "Mark complete") {
            model.change(itemID, to: .completed(!item.completed))
          }
          Button(item.archived ? "Restore task" : "Archive task") {
            model.change(itemID, to: .archived(!item.archived))
          }
        }.disabled(model.pending > 0)
        #if os(iOS)
          Section("iPhone reminder") {
            if let scheduled = item.reminder {
              Text(scheduled.formatted())
              Button("Remove reminder") { model.change(itemID, to: .reminder(nil)) }
            }
            DatePicker("Remind me", selection: $date, in: Date()...)
            Button("Schedule reminder") { Task { await model.requestReminder(itemID, at: date) } }
              .disabled(item.completed || item.archived || model.pending > 0)
            Text(
              "Reminders are delivered on iPhone. Your system settings control notification previews."
            ).font(.footnote).foregroundStyle(.secondary)
          }
        #endif
      }
    }.navigationTitle("Task details").task {
      if let item {
        title = item.title
        group = item.group
        date = max(Date(), item.reminder ?? date)
      }
    }
  }
}
