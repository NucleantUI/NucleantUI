//
//  Plan.swift
//  Pomodoro
//
//  What to work on in the next focus sessions, kept between launches.
//
//  The panel showing it sits in `PomodoroView`'s body, which the ticker
//  rebuilds every second — so a new `PlanPanel` struct is made every
//  second. The panel owns its `FocusPlan` through `@State`, and `@State`
//  makes its initial value once, when the panel first appears: the plan
//  file is read at launch, not once a second, and the plan the panel keeps
//  is that same instance for as long as the panel is on screen.
//

import Foundation
import NucleantUI
import Observation

// MARK: - Model

@MainActor
@Observable
final class FocusPlan {
    struct Task: Identifiable, Codable, Equatable {
        var id = UUID()
        var title: String
        var isDone = false
    }

    private(set) var tasks: [Task] = []
    private let file: URL?

    /// Reads the saved plan — the work the panel's `@State` must not repeat.
    init() {
        file = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pomodoro", isDirectory: true)
            .appendingPathComponent("plan.json")
        if let file, let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([Task].self, from: data) {
            tasks = saved
        }
    }

    var remaining: Int { tasks.filter { !$0.isDone }.count }

    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        tasks.append(Task(title: title))
        save()
    }

    func setDone(_ id: Task.ID, _ isDone: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isDone = isDone
        save()
    }

    func clearDone() {
        tasks.removeAll { $0.isDone }
        save()
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(tasks) else { return }
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: file)
    }
}

// MARK: - Panel

@View
struct PlanPanel {
    let tint: Color
    @State private var plan = FocusPlan()
    @State private var draft = ""

    var body: some View {
        let plan = self.plan
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Plan")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(plan.remaining == 1 ? "1 to go" : "\(plan.remaining) to go")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Add a task", text: $draft)
                    .onSubmit(add)
                    .frame(maxWidth: .infinity)
                Button("Add", action: add)
                    .tint(tint)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if plan.tasks.isEmpty {
                Text("Write down what the next sessions are for.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(plan.tasks) { task in
                            Toggle(task.title, isOn: Binding(
                                get: { task.isDone },
                                set: { plan.setDone(task.id, $0) }
                            ))
                            .foregroundStyle(task.isDone ? .secondary : .primary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
            }

            Button("Clear done") { plan.clearDone() }
                .tint(Theme.muted)
                .disabled(plan.tasks.allSatisfy { !$0.isDone })
        }
        .padding(18)
        .frame(width: 260)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
        .cornerRadius(16)
    }

    func add() {
        plan.add(draft)
        draft = ""
    }
}

@Preview("Plan")
@MainActor
func planPanelPreview() -> some View {
    PlanPanel(tint: .green)
        .frame(width: 320, height: 420)
        .background(Theme.panel)
}
