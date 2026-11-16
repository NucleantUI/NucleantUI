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

/// Keeps the texture its view hands it, as a video player does.
@MainActor
final class PhaseTextureSource: TextureSource {
    typealias Node = NucleantRenderNode
    private(set) var texture: ViewTexture<NucleantRenderNode>?

    func textureDidChange(_ texture: ViewTexture<NucleantRenderNode>) {
        self.texture = texture
    }

    func textureDidDisappear(_ texture: ViewTexture<NucleantRenderNode>) {
        self.texture = nil
    }
}

@View
struct PhaseTextureScreen {
    let source: PhaseTextureSource

    var body: some View {
        TextureView(source: source)
            .frame(width: 40, height: 30)
    }
}

/// A texture view that comes in once the counter is past zero.
@View
struct PhaseLateTextureScreen {
    let counter: PhaseCounter
    let source: PhaseTextureSource

    var body: some View {
        VStack {
            Text("\(counter.value)")
            if counter.value > 0 {
                TextureView(source: source)
                    .frame(width: 40, height: 30)
            }
        }
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

        /// A presented window showing `root`, kept for the process's lifetime.
        func presentedWindow<V: View>(_ root: V) throws -> HostingWindow<NucleantRenderNode> {
            _ = NSApplication.shared
            let window = HostingWindow<NucleantRenderNode>(title: "Phase", width: 160, height: 120, root: root)
            try window.present()
            Self.presented.append(window)
            return window
        }

        /// A frame of `texture`'s size, written as a decoder would.
        func writeFrame(into texture: ViewTexture<NucleantRenderNode>) -> Bool {
            let width = texture.pixelWidth, height = texture.pixelHeight
            let pixels = [UInt8](repeating: 0x80, count: width * height * 4)
            return pixels.withUnsafeBytes {
                texture.write(bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: width * 4)
            }
        }

        @Test func aTextureTakesNoFramesInTheBackground() async throws {
            let source = PhaseTextureSource()
            let window = try presentedWindow(PhaseTextureScreen(source: source))
            defer { window.platformWindow?.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(300))
            let texture = try #require(source.texture)
            #expect(writeFrame(into: texture))

            window.on_phase_background()
            #expect(!writeFrame(into: texture))
            #expect(texture.readPixels() == nil)

            window.on_phase_inactive()
            #expect(writeFrame(into: texture))
            #expect(texture.readPixels() != nil)
        }

        /// A view that comes in while the window is in the background gets
        /// its render node — and its source its texture — once it is back.
        @Test func aViewThatComesInTheBackgroundGetsItsNodeOnceBack() async throws {
            let source = PhaseTextureSource()
            let counter = PhaseCounter()
            let window = try presentedWindow(PhaseLateTextureScreen(counter: counter, source: source))
            defer { window.platformWindow?.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(300))
            let engine = try #require(window.renderEngine)
            let nodesBefore = engine.nodes.count

            window.on_phase_background()
            await mainQueueTurn()
            counter.value = 1
            try await Task.sleep(for: .milliseconds(300))
            #expect(engine.nodes.count == nodesBefore)
            #expect(source.texture == nil)

            window.on_phase_active()
            try await Task.sleep(for: .milliseconds(300))
            #expect(engine.nodes.count > nodesBefore)
            #expect(source.texture != nil)
        }

        /// The window canvas: the node that fills the window.
        func canvasSize(_ engine: NucleantRenderEngine) -> (Int, Int)? {
            for node in engine.nodes where node.compositesToWindow && node.compositeRect == nil {
                if case .skia(let canvas) = node.context { return (Int(canvas.width), Int(canvas.height)) }
            }
            return nil
        }

        @Test func aResizeInTheBackgroundWaitsForTheWindowToBeBack() async throws {
            let counter = PhaseCounter()
            let window = try presentedWindow(PhaseCounterView(counter: counter))
            defer { window.platformWindow?.orderOut(nil) }
            try await Task.sleep(for: .milliseconds(300))
            let engine = try #require(window.renderEngine)
            let before = try #require(canvasSize(engine))

            window.on_phase_background()
            await mainQueueTurn()
            window.platformWindow?.setContentSize(NSSize(width: 220, height: 170))
            try await Task.sleep(for: .milliseconds(300))
            let away = try #require(canvasSize(engine))
            #expect(away == before)

            window.on_phase_active()
            let back = try #require(canvasSize(engine))
            #expect(back.0 == window.win_rect.z && back.1 == window.win_rect.w)
            #expect(back.0 > before.0 && back.1 > before.1)
        }
        #endif
    }
}
