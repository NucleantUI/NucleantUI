//
//  WindowSizingTests.swift
//  NucleantUITests
//
//  `defaultSize`, `windowResizability` and `windowIdealSize`: what each
//  scene modifier settles for its windows, and the content sizes a window's
//  limits are measured from.
//

import Observation
import Testing
import NucleantWindow
@testable import NucleantUI

/// A scene of the app's own that sizes the window group inside it.
struct SizedScenes: Scene {
    var body: some Scene {
        WindowGroup("Inner") { EmptyView() }
            .defaultSize(width: 400, height: 300)
    }
}

/// A box whose size limits are its state's.
@View
struct ResizableBox {
    let model: BoxModel

    var body: some View {
        Color.red
            .frame(minWidth: model.minimum, maxWidth: 500, minHeight: 100, maxHeight: 500)
    }
}

@MainActor @Observable
final class BoxModel {
    var minimum: Double = 200

    func grow() {
        minimum = 300
    }
}

@MainActor
@Suite
struct WindowSizingTests {

    // MARK: Scene modifiers

    @Test func aWindowGroupHasNoSizeOfItsOwn() {
        let windows: [HostingWindow<NucleantRenderNode>] = WindowGroup("Plain") { EmptyView() }._makeWindows()
        let window = windows[0]
        #expect(window.sizing.defaultSize == nil)
        #expect(window.sizing.resizability == nil)
        #expect(window.sizing.idealSize == nil)
    }

    @Test func modifiersSettleTheWindowsSizing() {
        let scene = WindowGroup("Sized") { EmptyView() }
            .defaultSize(width: 640, height: 480)
            .windowResizability(.contentSize)
            .windowIdealSize(.fitToContent)
            .commands {}
        let windows: [HostingWindow<NucleantRenderNode>] = scene._makeWindows()
        let window = windows[0]
        #expect(window.sizing.defaultSize == Size(width: 640, height: 480))
        #expect(window.sizing.resizability == .contentSize)
        #expect(window.sizing.idealSize == .fitToContent)
    }

    @Test func theModifierNearestTheSceneWins() {
        let scene = WindowGroup("Twice") { EmptyView() }
            .defaultSize(Size(width: 320, height: 240))
            .windowResizability(.contentMinSize)
            .defaultSize(width: 1000, height: 800)
            .windowResizability(.contentSize)
        let windows: [HostingWindow<NucleantRenderNode>] = scene._makeWindows()
        let window = windows[0]
        #expect(window.sizing.defaultSize == Size(width: 320, height: 240))
        #expect(window.sizing.resizability == .contentMinSize)
    }

    @Test func aModifierOnACompositeSceneSizesEveryWindowNotAlreadySized() {
        @SceneBuilder var body: some Scene {
            SizedScenes()
            WindowGroup("Outer") { EmptyView() }
        }
        let windows: [HostingWindow<NucleantRenderNode>] = body.defaultSize(width: 800, height: 600)._makeWindows()
        #expect(windows.map(\.title) == ["Inner", "Outer"])
        #expect(windows.map(\.sizing.defaultSize) == [Size(width: 400, height: 300), Size(width: 800, height: 600)])
    }

    // MARK: What gets measured

    @Test func automaticResizabilityMeasuresTheMinimumOnly() {
        #expect(WindowSizing().measurements == [.minimum])
        #expect(WindowSizing(resizability: .automatic).measurements == [.minimum])
        #expect(WindowSizing(resizability: .contentMinSize).measurements == [.minimum])
    }

    @Test func contentSizeResizabilityMeasuresBothLimits() {
        #expect(WindowSizing(resizability: .contentSize).measurements == [.minimum, .maximum])
    }

    @Test func idealSizeMeasuresWhatZoomingGoesTo() {
        #expect(WindowSizing(idealSize: .automatic).measurements == [.minimum])
        #expect(WindowSizing(idealSize: .fitToContent).measurements == [.minimum, .ideal])
        #expect(WindowSizing(idealSize: .maximum).measurements == [.minimum, .maximum])
    }

    // MARK: Clamping and zooming

    @Test func aSizeIsClampedIntoTheLimits() {
        let limits = ContentSizeLimits(
            minimum: Size(width: 300, height: 200),
            maximum: Size(width: 600, height: .infinity)
        )
        #expect(WindowSizing.clamp(Size(width: 100, height: 100), to: limits) == Size(width: 300, height: 200))
        #expect(WindowSizing.clamp(Size(width: 900, height: 900), to: limits) == Size(width: 600, height: 900))
        #expect(WindowSizing.clamp(Size(width: 400, height: 400), to: ContentSizeLimits()) == Size(width: 400, height: 400))
    }

    @Test func zoomingGoesWhereTheIdealSizeSays() {
        let limits = ContentSizeLimits(
            minimum: Size(width: 300, height: 200),
            maximum: Size(width: 600, height: 500),
            ideal: Size(width: 100, height: 400)
        )
        #expect(WindowSizing(idealSize: .automatic).zoomSize(for: limits) == nil)
        // Never outside the limits, whatever the content's ideal says.
        #expect(WindowSizing(idealSize: .fitToContent).zoomSize(for: limits) == Size(width: 300, height: 400))
        #expect(WindowSizing(idealSize: .maximum).zoomSize(for: limits) == Size(width: 600, height: 500))
        // No maximum to zoom to: the system's own zoom.
        let unbounded = ContentSizeLimits(maximum: Size(width: .infinity, height: 500))
        #expect(WindowSizing(idealSize: .maximum).zoomSize(for: unbounded) == nil)
    }

    @Test func onlyEqualLimitsMakeAFixedWindow() {
        let size = Size(width: 400, height: 300)
        #expect(ContentSizeLimits(minimum: size, maximum: size).isFixed)
        #expect(!ContentSizeLimits(minimum: size, maximum: Size(width: 400, height: 301)).isFixed)
        #expect(!ContentSizeLimits(minimum: size).isFixed)
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct ContentSizeLimitTests {

        private func measured<V: View>(
            _ view: V,
            _ measurements: ContentSizeLimits.Measurements = [.minimum, .maximum, .ideal]
        ) -> ContentSizeLimits {
            let harness = Harness(view)
            harness.host.measuredContentSizes = measurements
            harness.host.update()
            return harness.host.contentSizeLimits
        }

        @Test func aFixedFrameIsAFixedWindow() {
            let limits = measured(Color.red.frame(width: 400, height: 300))
            #expect(limits.minimum == Size(width: 400, height: 300))
            #expect(limits.maximum == Size(width: 400, height: 300))
            #expect(limits.isFixed)
        }

        @Test func aFlexibleFrameGivesTheWindowItsRange() {
            let limits = measured(
                Color.red.frame(minWidth: 300, maxWidth: 440, minHeight: 480, maxHeight: 680)
            )
            #expect(limits.minimum == Size(width: 300, height: 480))
            #expect(limits.maximum == Size(width: 440, height: 680))
            #expect(!limits.isFixed)
        }

        @Test func theIdealSizeIsTheContentsOwn() {
            let limits = measured(
                Color.red
                    .frame(width: 360, height: 600)
                    .frame(minWidth: 300, maxWidth: 440, minHeight: 480, maxHeight: 680)
            )
            #expect(limits.ideal == Size(width: 360, height: 600))
        }

        @Test func contentThatTakesAnySizeLimitsNothing() {
            let limits = measured(Color.red)
            #expect(limits.minimum == Size(width: 0, height: 0))
            #expect(limits.maximum == Size(width: .infinity, height: .infinity))
        }

        @Test func onlyWhatTheWindowAsksForIsMeasured() {
            let limits = measured(Color.red.frame(width: 400, height: 300), [.minimum])
            #expect(limits.minimum == Size(width: 400, height: 300))
            #expect(limits.maximum == nil)
            #expect(limits.ideal == nil)
            #expect(measured(Color.red.frame(width: 400, height: 300), []) == ContentSizeLimits())
        }

        @Test func aStateChangeThatMovesTheLimitsIsReported() async {
            let model = BoxModel()
            let harness = Harness(ResizableBox(model: model))
            var reported: [ContentSizeLimits] = []
            harness.host.onContentSizeLimitsChange = { reported.append($0) }
            harness.host.measuredContentSizes = [.minimum, .maximum]
            harness.host.update()
            #expect(reported.map(\.minimum) == [Size(width: 200, height: 100)])

            // A resize lays out again but changes no view: nothing to report.
            harness.host.setSize(Size(width: 300, height: 300))
            harness.host.update()
            #expect(reported.count == 1)

            model.grow()
            await harness.settle()
            #expect(reported.map(\.minimum) == [Size(width: 200, height: 100), Size(width: 300, height: 100)])
            #expect(reported.last?.maximum == Size(width: 500, height: 500))
        }
    }
}
