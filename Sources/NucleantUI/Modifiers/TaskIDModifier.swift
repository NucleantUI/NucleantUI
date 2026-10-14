//
//  TaskIDModifier.swift
//  NucleantUI
//
//  `.task(id:)`: an asynchronous task with the lifetime of the view it
//  modifies, replaced whenever `id` changes. The running task and the `id` it
//  was started for are held in the modifier's own `@State`, so they are made
//  the first time the view is built and let go of when the view leaves the
//  tree — and letting go of them cancels the task.
//

extension View {

    /// Starts `action` as a task when this view appears, and again — with
    /// the running one cancelled — whenever `value` changes; cancels it when
    /// the view leaves the tree.
    ///
    /// The restarted task is the latest build's `action`, so it sees what
    /// that build captured.
    ///
    /// ```swift
    /// Text(status ?? "Signed Out")
    ///     .task(id: server) {
    ///         for await value in server.statusUpdates {
    ///             status = value
    ///         }
    ///     }
    /// ```
    public func task<T: Equatable>(
        id value: T,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @MainActor () async -> Void
    ) -> some View {
        _TaskIDView(content: self, id: value, priority: priority, action: action)
    }
}

/// `.task(id:)`'s view: its content, and the task it started for `id`.
@View
struct _TaskIDView<Content: View, ID: Equatable> {
    let content: Content
    let id: ID
    let priority: TaskPriority
    let action: @MainActor () async -> Void
    @State private var running = IdentifiedTask<ID>()

    var body: some View {
        let _ = running.start(id: id, priority: priority, action)
        content
    }
}

/// The task one `.task(id:)` started, and the `id` it started it for.
@MainActor
final class IdentifiedTask<ID: Equatable> {
    private var id: ID?
    private var task: Task<Void, Never>?

    /// Start `action`, unless the task running is for an equal `id`; one
    /// running for another `id` is cancelled first.
    func start(id: ID, priority: TaskPriority, _ action: @escaping @MainActor () async -> Void) {
        if task != nil, self.id == id { return }
        task?.cancel()
        self.id = id
        task = Task(priority: priority) { await action() }
    }

    /// The view left the tree, and its state with it.
    deinit {
        task?.cancel()
    }
}
