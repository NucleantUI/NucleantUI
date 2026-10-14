//
//  TaskModifier.swift
//  NucleantUI
//
//  `.task`: an asynchronous task with the lifetime of the view it modifies.
//  The running task is held in the modifier's own `@State`, so it is made
//  the first time the view is built and let go of when the view leaves the
//  tree — and letting go of it cancels the task.
//

extension View {

    /// Starts `action` as a task when this view appears, and cancels it when
    /// the view leaves the tree if it hasn't finished by then.
    ///
    /// The task runs on the main actor, so it can write the view's state;
    /// each `await` gives the frames their turn.
    ///
    /// ```swift
    /// Text(message)
    ///     .task {
    ///         for await line in feed.lines {
    ///             message = line
    ///         }
    ///     }
    /// ```
    public func task(
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @MainActor () async -> Void
    ) -> some View {
        _TaskView(content: self, priority: priority, action: action)
    }
}

/// `.task`'s view: its content, and the task it started.
@View
struct _TaskView<Content: View> {
    let content: Content
    let priority: TaskPriority
    let action: @MainActor () async -> Void
    @State private var running = AppearanceTask()

    var body: some View {
        let _ = running.start(priority: priority, action)
        content
    }
}

/// The task one `.task` started — once, for as long as its view stands.
@MainActor
final class AppearanceTask {
    private var task: Task<Void, Never>?

    func start(priority: TaskPriority, _ action: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        task = Task(priority: priority) { await action() }
    }

    /// The view left the tree, and its state with it.
    deinit {
        task?.cancel()
    }
}
