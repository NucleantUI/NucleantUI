//
//  ChangeAndTaskTests.swift
//  NucleantUITests
//
//  `.onChange` and `.task`, hosted: what runs, with which values, and when
//  a task is started, restarted and cancelled.
//

import Observation
import Testing
@testable import NucleantUI

/// What the views under test are built from, changed by the tests.
@MainActor
@Observable
final class Knobs {
    var value = 0
    /// Read alongside `value`, so changing it rebuilds without a change.
    var unrelated = 0
    var isShown = true
}

/// A task's body that runs until the task is cancelled. No timer: the stream
/// never yields, and iterating it ends with the cancellation. (A 60 s
/// `Task.sleep` stood in for this, but in the browser Swift's own executor
/// serves deadlines out of order, so the tests' short waits sat behind it.)
private func untilCancelled() async {
    let (stream, continuation) = AsyncStream<Never>.makeStream()
    for await _ in stream {}
    withExtendedLifetime(continuation) {}
}

@View
struct ChangeWatcher {
    let knobs: Knobs
    let log: Log
    let initial: Bool

    var body: some View {
        let unrelated = knobs.unrelated
        Color.orange
            .onChange(of: knobs.value, initial: initial) { old, new in
                log("\(old) → \(new), unrelated \(unrelated)")
            }
            .onChange(of: knobs.value) {
                log("changed")
            }
    }
}

@View
struct ShownWatcher {
    let knobs: Knobs
    let log: Log

    var body: some View {
        VStack {
            if knobs.isShown {
                Color.orange.onChange(of: knobs.value) { old, new in
                    log("\(old) → \(new)")
                }
            }
        }
    }
}

@View
struct TaskRunner {
    let knobs: Knobs
    let log: Log

    var body: some View {
        VStack {
            if knobs.isShown {
                Color.orange.task {
                    log("started")
                    await untilCancelled()
                    log(Task.isCancelled ? "cancelled" : "finished")
                }
            }
        }
    }
}

@View
struct IdentifiedTask {
    let knobs: Knobs
    let log: Log

    var body: some View {
        let id = knobs.value
        let unrelated = knobs.unrelated
        Color.orange.task(id: id) {
            log("started \(id), unrelated \(unrelated)")
            await untilCancelled()
            log(Task.isCancelled ? "cancelled \(id)" : "finished \(id)")
        }
    }
}

/// A task that writes its view's own state.
@View
struct SelfCountingTask {
    let shown: Log
    @State private var count = 0

    var body: some View {
        shown("\(count)")
        return Color.orange.task {
            while count < 3 {
                await Task.yield()
                count += 1
            }
        }
    }
}

extension Harness {
    /// Write the views' inputs and rebuild before anything else can run.
    /// The invalidation queue is the process's: a host in another suite,
    /// given a turn while this one waits, would otherwise take the write.
    func change(_ write: () -> Void) async {
        write()
        host.update()
        await settle()
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ChangeAndTaskTests {

        @Test func onChangeRunsWithTheOldAndNewValue() async {
            let knobs = Knobs()
            let log = Log()
            let harness = Harness(ChangeWatcher(knobs: knobs, log: log, initial: false))
            await harness.settle()
            #expect(log.take() == [], "nothing changed yet, and not initial")

            await harness.change { knobs.value = 1 }
            #expect(log.take() == ["changed", "0 → 1, unrelated 0"], "outermost first, as onAppear")

            await harness.change { knobs.unrelated = 7 }
            #expect(log.take() == [], "rebuilt, but the value is the same")

            await harness.change {
                knobs.value = 2
                knobs.unrelated = 8
            }
            #expect(log.take() == ["changed", "1 → 2, unrelated 8"], "the action is the new build's")
        }

        @Test func onChangeInitialRunsOnAppear() async {
            let knobs = Knobs()
            knobs.value = 5
            let log = Log()
            let harness = Harness(ChangeWatcher(knobs: knobs, log: log, initial: true))
            await harness.settle()
            #expect(log.take() == ["5 → 5, unrelated 0"], "the two-value one only: the other isn't initial")

            await harness.change { knobs.unrelated = 1 }
            #expect(log.take() == [], "once, not once per build")
        }

        @Test func onChangeStartsOverWhenItsViewComesBack() async {
            let knobs = Knobs()
            let log = Log()
            let harness = Harness(ShownWatcher(knobs: knobs, log: log))
            await harness.change { knobs.value = 1 }
            #expect(log.take() == ["0 → 1"])

            await harness.change { knobs.isShown = false }
            await harness.change { knobs.value = 2 }
            await harness.change { knobs.isShown = true }
            #expect(log.take() == [], "back with 2, which is where it starts")

            await harness.change { knobs.value = 3 }
            #expect(log.take() == ["2 → 3"])
        }

        @Test func taskIsCancelledWhenItsViewLeaves() async {
            let knobs = Knobs()
            let log = Log()
            let harness = Harness(TaskRunner(knobs: knobs, log: log))
            await harness.settle()
            #expect(log.take() == ["started"])

            await harness.change { knobs.unrelated = 1 }
            #expect(log.take() == [], "a rebuild leaves it running")

            await harness.change { knobs.isShown = false }
            await harness.settle()
            #expect(log.take() == ["cancelled"])

            await harness.change { knobs.isShown = true }
            await harness.settle()
            #expect(log.take() == ["started"], "back in the tree, a new task")
        }

        @Test func taskRestartsWhenItsIDChanges() async {
            let knobs = Knobs()
            let log = Log()
            let harness = Harness(IdentifiedTask(knobs: knobs, log: log))
            await harness.settle()
            #expect(log.take() == ["started 0, unrelated 0"])

            await harness.change { knobs.unrelated = 1 }
            #expect(log.take() == [], "same id")

            await harness.change {
                knobs.value = 1
                knobs.unrelated = 2
            }
            await harness.settle()
            // Two tasks on the main actor: which of them is given its turn first
            // is the executor's business.
            #expect(Set(log.take()) == ["cancelled 0", "started 1, unrelated 2"], "the new build's action")
        }

        @Test func taskWritesItsViewsState() async {
            let shown = Log()
            let harness = Harness(SelfCountingTask(shown: shown))
            for _ in 0..<6 {
                await harness.settle()
            }
            #expect(shown.entries.first == "0")
            #expect(shown.entries.last == "3")
        }

        @Test func tasksAreCancelledWithTheirHost() async {
            let knobs = Knobs()
            let log = Log()
            var harness: Harness? = Harness(TaskRunner(knobs: knobs, log: log))
            await harness?.settle()
            #expect(log.take() == ["started"])

            harness = nil
            try? await Task.sleep(for: .seconds(0.05))
            #expect(harness == nil)
            #expect(log.take() == ["cancelled"])
        }
    }
}
