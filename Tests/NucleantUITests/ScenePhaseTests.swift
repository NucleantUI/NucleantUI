//
//  ScenePhaseTests.swift
//  NucleantUITests
//
//  `ScenePhase` and `\.scenePhase`: the phase a window's platform puts it
//  in reaches the views that read it, `onChange(of: scenePhase)` runs
//  without waiting for a display-link tick, and a window in the background
//  draws nothing.
//

import Dispatch
import Observation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import NucleantUI

/// Reads the phase, and notes each build and each change.
@View
struct PhaseWatcher {
    let log: Log
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let _ = log("watcher \(scenePhase)")
        Color.orange
            .onChange(of: scenePhase) { old, new in
                log("\(old) → \(new)")
            }
    }
}

/// Reads nothing from the environment.
@View
struct PhaseIgnorer {
    let log: Log

    var body: some View {
        let _ = log("ignorer")
        Color.blue
    }
}

@View
struct PhaseScreen {
    let log: Log

    var body: some View {
        HStack {
            PhaseWatcher(log: log)
            PhaseIgnorer(log: log)
        }
    }
}

/// What a window shows, changed while it is out of sight.
@MainActor
@Observable
final class PhaseCounter {
    var value = 0
}

@View
struct PhaseCounterView {
    let counter: PhaseCounter

    var body: some View {
        Text("\(counter.value)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
@Suite
struct ScenePhaseTests {
    @Test func phasesAreOrderedFromBackgroundToActive() {
        #expect(ScenePhase.background < .inactive)
        #expect(ScenePhase.inactive < .active)
        #expect([ScenePhase.active, .background, .inactive].sorted() == [.background, .inactive, .active])
    }

    @Test func outsideAWindowTheSceneIsActive() {
        #expect(EnvironmentValues().scenePhase == .active)
    }
}

/// Let the main queue run what was queued on it before this: the frame a
/// window queued.
@MainActor
private func mainQueueTurn() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

extension HostedViews {

    @MainActor
    @Suite
    struct WindowPhaseTests {

        func window<V: View>(_ view: V) -> HostingWindow<NucleantRenderNode> {
            let window = HostingWindow<NucleantRenderNode>(title: "Phase", width: 200, height: 200, root: view)
            window.on_size(w: 200, h: 200)
            window.host.update()
            return window
        }

        @Test func thePhaseReachesTheViewsThatReadIt() async {
            let log = Log()
            let window = window(PhaseScreen(log: log))
            #expect(log.take() == ["watcher active", "ignorer"])

            // No display-link tick comes: the window runs the frame itself.
            window.on_phase_inactive()
            await mainQueueTurn()
            #expect(log.take() == ["watcher inactive", "active → inactive"])
            #expect(window.host.environment.scenePhase == .inactive)

            window.on_phase_background()
            await mainQueueTurn()
            #expect(log.take() == ["watcher background", "inactive → background"])

            window.on_phase_active()
            await mainQueueTurn()
            #expect(log.take() == ["watcher active", "background → active"])
            #expect(window.scenePhase == .active)
        }

        @Test func thePhaseTheWindowIsInAlreadyChangesNothing() async {
            let log = Log()
            let window = window(PhaseScreen(log: log))
            _ = log.take()

            window.on_phase_active()
            await mainQueueTurn()
            #expect(log.take().isEmpty)

            window.on_phase_background()
            await mainQueueTurn()
            _ = log.take()
            window.on_phase_background()
            await mainQueueTurn()
            #expect(log.take().isEmpty)
        }

        #if os(macOS)
        /// Presented windows, kept for the process's lifetime as the app
        /// keeps its own: a window is never taken down.
        static var presented: [HostingWindow<NucleantRenderNode>] = []

        @Test func aWindowInTheBackgroundDrawsNothingUntilItIsBack() async throws {
            _ = NSApplication.shared
            let counter = PhaseCounter()
            let window = HostingWindow<NucleantRenderNode>(title: "Phase", width: 160, height: 120, root: PhaseCounterView(counter: counter))
            try window.present()
            Self.presented.append(window)
            defer { window.platformWindow?.orderOut(nil) }
            let engine = try #require(window.renderEngine)
            var draws = 0
            engine.onUpdate = { _ in draws += 1 }

            // The display link draws the first frames.
            try await Task.sleep(for: .milliseconds(300))
            #expect(draws > 0)

            // The window stays on screen, so its display link keeps ticking:
            // only the phase keeps the engine idle, through a change too.
            window.on_phase_background()
            await mainQueueTurn()
            draws = 0
            counter.value += 1
            try await Task.sleep(for: .milliseconds(300))
            #expect(draws == 0)

            // Back, and what changed meanwhile is drawn.
            window.on_phase_active()
            try await Task.sleep(for: .milliseconds(300))
            #expect(draws > 0)
        }
        #endif
    }
}
