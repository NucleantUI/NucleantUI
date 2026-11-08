//
//  TransitionTests.swift
//  NucleantUITests
//
//  `Transition`, hosted: the phases a transition's body is built in and in
//  what order, custom transitions — the body's own modifiers doing the
//  animating — `AnyTransition` erasing any of them, the compositions, how
//  long a removed view stays, and what it looks like and where it is hit
//  on the way: read off the phases asked for, an `Animatable` modifier's
//  values, the pixels drawn and the views a tap reaches.
//

import Observation
import Testing
import NucleantSkia
@testable import NucleantUI

/// What the views under test are built from, changed by the tests.
@MainActor
@Observable
final class Stage {
    var isShown: Bool
    var items: [Int]

    init(isShown: Bool = false, items: [Int] = []) {
        self.isShown = isShown
        self.items = items
    }

    func show() { isShown = true }
    func hide() { isShown = false }
    func add(_ item: Int) { items.append(item) }
    func remove(_ item: Int) { items.removeAll { $0 == item } }
    func replace(with item: Int) { items = [item] }
}

// MARK: - Transitions under test

/// Logs every phase its body is built in, and fades the view.
struct PhaseRecorder: Transition {
    let name: String
    let log: Log

    func body(content: Content, phase: TransitionPhase) -> some View {
        let _ = log("\(name) \(phase)")
        content.opacity(phase.isIdentity ? 1 : 0)
    }
}

/// An amount, animated as the modifier's own data, logged at every value
/// the view is built with.
struct Probe: ViewModifier, Animatable {
    var amount: Double
    let log: Log

    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        let _ = log("\(Int(amount.rounded()))")
        content
    }
}

/// A transition made of an `Animatable` modifier of its own: 100 off
/// screen, 0 shown.
struct ProbeTransition: Transition {
    let log: Log

    func body(content: Content, phase: TransitionPhase) -> some View {
        content.modifier(Probe(amount: phase.isIdentity ? 0 : 100, log: log))
    }
}

/// The documentation's example: a fade and a turn.
struct RotatingFadeTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1.0 : 0.0)
            .rotationEffect(phase.rotation)
    }
}

extension TransitionPhase {
    fileprivate var rotation: Angle {
        switch self {
        case .willAppear: return .degrees(30)
        case .identity: return .zero
        case .didDisappear: return .degrees(-30)
        }
    }
}

/// A transition whose identity phase changes the view: half faded the whole
/// time it is shown.
struct HalfFaded: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content.opacity(phase.isIdentity ? 0.5 : 0)
    }
}

// MARK: - Views under test

/// A red 50-point square at the top-leading corner while the stage shows
/// it, with `transition`.
@View
struct Toggled<T: Transition> {
    let stage: Stage
    let transition: T

    var body: some View {
        ZStack {
            if stage.isShown {
                Color.red.frame(width: 50, height: 50).transition(transition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The same, with the transition erased.
@View
struct ToggledAny {
    let stage: Stage
    let transition: AnyTransition

    var body: some View {
        ZStack {
            if stage.isShown {
                Color.red.frame(width: 50, height: 50).transition(transition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A blue square catching taps behind a red one the stage shows and hides
/// — each logs its own.
@View
struct Covered {
    let stage: Stage
    let log: Log

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.blue.frame(width: 50, height: 50).onTapGesture { log("back") }
            if stage.isShown {
                Color.red.frame(width: 50, height: 50)
                    .onTapGesture { log("front") }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Where a reader 100 points across is in the window, while the stage shows
/// it, arriving and leaving with `transition`.
@View
struct MovingReader<T: Transition> {
    let stage: Stage
    let log: Log
    let transition: T

    var body: some View {
        ZStack {
            if stage.isShown {
                GeometryReader { proxy in
                    Color.blue.preference(key: ReaderLeadingKey.self, value: proxy.frame(in: .global).minX)
                }
                .frame(width: 50, height: 50)
                .transition(transition)
            }
        }
        .padding(.leading, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onPreferenceChange(ReaderLeadingKey.self) { log("at \(Int($0.rounded()))") }
    }
}

/// A tappable square moved 100 points across while the stage says so.
@View
struct Shifted {
    let stage: Stage
    let log: Log

    var body: some View {
        Color.red
            .frame(width: 50, height: 50)
            .onTapGesture { log("tap") }
            .offset(x: stage.isShown ? 100 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A grid of the stage's items, one row each: the first column 100 wide
/// for item 0 and 20 for the rest, the second a tappable cell.
@View
struct GridOfRows {
    let stage: Stage
    let log: Log

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(stage.items, id: \.self) { item in
                GridRow {
                    Color.red.frame(width: item == 0 ? 100 : 20, height: 20)
                    Color.blue.frame(width: 20, height: 20).onTapGesture { log("cell \(item)") }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The stage's items as squares stacked on each other, item 0 red and the
/// rest blue, each over the one before.
@View
struct StackedCards {
    let stage: Stage

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(stage.items, id: \.self) { item in
                (item == 0 ? Color.red : Color.blue).frame(width: 50, height: 50)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The stage's one item as a square — red, blue, green — replaced by the
/// next: on at once, off with a fade.
@View
struct SwappedSquare {
    let stage: Stage

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(stage.items, id: \.self) { item in
                ([Color.red, Color.blue, Color.green][item % 3]).frame(width: 50, height: 50)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Pixels

/// A host drawing into a 200×200 CPU surface, read back pixel by pixel.
@MainActor
final class PaintedHarness {
    let harness: Harness
    let surface = SkSurfaces.raster(width: 200, height: 200)!

    init<V: View>(_ view: V) {
        harness = Harness(view)
        harness.host.renderer = SkiaDisplayRenderer(surface: surface)
        harness.host.invalidate()
        harness.host.update()
    }

    func update() { harness.host.update() }
    func settle(_ seconds: Double) async { await harness.settle(seconds) }

    /// The frame after a change, on time, as a display would draw it: an
    /// animation's clock starts from it, and a first frame that comes late
    /// would show its curve from the beginning (`AnimationRun`).
    func nextFrame() async { await harness.settle(1.0 / 60) }

    func alpha(_ x: Int, _ y: Int) -> UInt8 {
        surface.readPixel(x: x, y: y)?.w ?? 0
    }

    func pixel(_ x: Int, _ y: Int) -> SIMD4<UInt8> {
        surface.readPixel(x: x, y: y) ?? SIMD4(0, 0, 0, 0)
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct TransitionTests {

        // MARK: Phases

        @Test func eachPhaseIsAskedForInTurn() {
            let log = Log()
            let stage = Stage()
            let harness = Harness(Toggled(stage: stage, transition: PhaseRecorder(name: "t", log: log)))
            #expect(log.take() == [])

            withAnimation(.linear(duration: 10)) { stage.show() }
            harness.host.update()
            #expect(log.take() == ["t willAppear", "t identity"])

            withAnimation(.linear(duration: 10)) { stage.hide() }
            harness.host.update()
            #expect(log.take() == ["t didDisappear"])

            // Back while leaving: straight to identity, never willAppear.
            withAnimation(.linear(duration: 10)) { stage.show() }
            harness.host.update()
            #expect(log.take() == ["t identity"])
        }

        @Test func aViewInAContainerBuiltWithItIsNotTransitioned() {
            let log = Log()
            let stage = Stage(isShown: true)
            _ = Harness(Toggled(stage: stage, transition: PhaseRecorder(name: "t", log: log)))
            // The transition of a view that is simply there is in identity.
            #expect(log.take() == ["t identity"])
        }

        @Test func aChangeThatDoesNotAnimateDoesNotTransition() {
            let log = Log()
            let stage = Stage()
            let harness = Harness(Toggled(stage: stage, transition: PhaseRecorder(name: "t", log: log)))
            stage.show()
            harness.host.update()
            #expect(log.take() == ["t identity"])
            stage.hide()
            harness.host.update()
            #expect(log.take() == [])
        }

        @Test func asymmetricMovesEachHalfInItsOwnPhase() {
            let log = Log()
            let stage = Stage()
            let transition = AsymmetricTransition(
                insertion: PhaseRecorder(name: "in", log: log),
                removal: PhaseRecorder(name: "out", log: log)
            )
            let harness = Harness(Toggled(stage: stage, transition: transition))

            withAnimation(.linear(duration: 10)) { stage.show() }
            harness.host.update()
            let arriving = log.take()
            #expect(arriving.filter { $0.hasPrefix("in ") } == ["in willAppear", "in identity"])
            #expect(arriving.filter { $0.hasPrefix("out ") } == ["out identity", "out identity"])

            withAnimation(.linear(duration: 10)) { stage.hide() }
            harness.host.update()
            let leaving = log.take()
            #expect(leaving.filter { $0.hasPrefix("in ") } == ["in identity"])
            #expect(leaving.filter { $0.hasPrefix("out ") } == ["out didDisappear"])
        }

        @Test func combinedMovesBothTogether() {
            let log = Log()
            let stage = Stage()
            let transition = PhaseRecorder(name: "a", log: log).combined(with: PhaseRecorder(name: "b", log: log))
            let harness = Harness(Toggled(stage: stage, transition: transition))

            withAnimation(.linear(duration: 10)) { stage.show() }
            harness.host.update()
            let arriving = log.take()
            #expect(arriving.filter { $0.hasPrefix("a ") } == ["a willAppear", "a identity"])
            #expect(arriving.filter { $0.hasPrefix("b ") } == ["b willAppear", "b identity"])
        }

        // MARK: A transition's own modifiers animate

        @Test func aCustomTransitionAnimatesItsOwnModifier() async {
            let log = Log()
            let stage = Stage()
            let harness = Harness(Toggled(stage: stage, transition: ProbeTransition(log: log)))
            _ = log.take()

            withAnimation(.linear(duration: 0.2)) { stage.show() }
            harness.host.update()
            for _ in 0..<20 { await harness.settle(0.02) }
            let arriving = log.take().compactMap(Int.init)
            #expect(arriving.first == 100)
            #expect(arriving.last == 0)
            #expect(arriving.count > 3)
            #expect(zip(arriving, arriving.dropFirst()).allSatisfy { $0 >= $1 })

            withAnimation(.linear(duration: 0.2)) { stage.hide() }
            harness.host.update()
            for _ in 0..<20 { await harness.settle(0.02) }
            let leaving = log.take().compactMap(Int.init)
            #expect(leaving.first == 0)
            #expect(leaving.last == 100)
            #expect(zip(leaving, leaving.dropFirst()).allSatisfy { $0 <= $1 })
        }

        @Test func anErasedTransitionIsTheTransitionItHolds() async {
            let log = Log()
            let stage = Stage()
            let harness = Harness(ToggledAny(stage: stage, transition: AnyTransition(ProbeTransition(log: log))))

            withAnimation(.linear(duration: 0.2)) { stage.show() }
            harness.host.update()
            for _ in 0..<20 { await harness.settle(0.02) }
            let arriving = log.take().compactMap(Int.init)
            #expect(arriving.first == 100)
            #expect(arriving.last == 0)
            #expect(arriving.count > 3)
        }

        @Test func aModifierTransitionAnimatesBetweenItsTwoModifiers() async {
            let log = Log()
            let stage = Stage()
            let transition = AnyTransition.modifier(
                active: Probe(amount: 100, log: log),
                identity: Probe(amount: 0, log: log)
            )
            let harness = Harness(ToggledAny(stage: stage, transition: transition))
            _ = log.take()

            withAnimation(.linear(duration: 0.2)) { stage.show() }
            harness.host.update()
            for _ in 0..<20 { await harness.settle(0.02) }
            let arriving = log.take().compactMap(Int.init)
            #expect(arriving.first == 100)
            #expect(arriving.last == 0)
            #expect(arriving.count > 3)
        }

        @Test func aViewBackWhileLeavingReturnsFromWhereItWas() async {
            let log = Log()
            let stage = Stage(isShown: true)
            let harness = Harness(Toggled(stage: stage, transition: ProbeTransition(log: log)))
            _ = log.take()

            withAnimation(.linear(duration: 1)) { stage.hide() }
            harness.host.update()
            for _ in 0..<5 { await harness.settle(0.1) }
            let leaving = log.take().compactMap(Int.init)
            let reached = leaving.last ?? 0
            #expect(reached > 10 && reached < 90)

            withAnimation(.linear(duration: 0.2)) { stage.show() }
            harness.host.update()
            for _ in 0..<20 { await harness.settle(0.02) }
            let back = log.take().compactMap(Int.init)
            // Turned around where it was — not started over from 100.
            #expect(back.allSatisfy { $0 <= reached + 10 })
            #expect(back.last == 0)
        }

        // MARK: What is drawn

        @Test func anOpacityTransitionFadesTheViewInAndOut() async {
            let stage = Stage()
            let painted = PaintedHarness(Toggled(stage: stage, transition: .opacity))
            #expect(painted.alpha(25, 25) == 0)

            withAnimation(.linear(duration: 0.6)) { stage.show() }
            painted.update()
            // Inserted where its fade starts.
            #expect(painted.alpha(25, 25) == 0)
            await painted.nextFrame()
            await painted.settle(0.3)
            let arriving = painted.alpha(25, 25)
            #expect(arriving > 25 && arriving < 230)
            await painted.settle(0.5)
            #expect(painted.alpha(25, 25) == 255)

            withAnimation(.linear(duration: 0.6)) { stage.hide() }
            painted.update()
            // Removed where its fade starts: still all there.
            #expect(painted.alpha(25, 25) == 255)
            await painted.nextFrame()
            await painted.settle(0.3)
            let leaving = painted.alpha(25, 25)
            #expect(leaving > 25 && leaving < 230)
            await painted.settle(0.5)
            await painted.settle(0.05)
            #expect(painted.alpha(25, 25) == 0)
        }

        @Test func theDocumentationsRotatingFadeTurnsAndFades() async {
            let stage = Stage()
            let painted = PaintedHarness(Toggled(stage: stage, transition: RotatingFadeTransition()))
            withAnimation(.linear(duration: 0.6)) { stage.show() }
            painted.update()
            await painted.nextFrame()
            await painted.settle(0.3)
            // Half faded, and turned: the square's corner is off its place.
            let middle = painted.alpha(25, 25)
            #expect(middle > 25 && middle < 230)
            await painted.settle(0.5)
            #expect(painted.alpha(25, 25) == 255)
            #expect(painted.alpha(2, 2) == 255)
        }

        @Test func anAttachedAnimationRunsWithoutWithAnimation() async {
            let stage = Stage()
            let painted = PaintedHarness(Toggled(stage: stage, transition: .opacity.animation(.linear(duration: 0.6))))

            stage.show()
            painted.update()
            #expect(painted.alpha(25, 25) == 0)
            await painted.nextFrame()
            await painted.settle(0.3)
            let arriving = painted.alpha(25, 25)
            #expect(arriving > 25 && arriving < 230)
            await painted.settle(0.5)
            #expect(painted.alpha(25, 25) == 255)

            stage.hide()
            painted.update()
            await painted.nextFrame()
            await painted.settle(0.3)
            let leaving = painted.alpha(25, 25)
            #expect(leaving > 25 && leaving < 230)
        }

        @Test func theIdentityTransitionRemovesAtOnce() async {
            let stage = Stage(isShown: true)
            let painted = PaintedHarness(Toggled(stage: stage, transition: .identity))
            #expect(painted.alpha(25, 25) == 255)
            withAnimation(.linear(duration: 10)) { stage.hide() }
            painted.update()
            #expect(painted.alpha(25, 25) == 0)
        }

        @Test func anIdentityPhaseThatChangesTheViewStaysOnIt() async {
            let stage = Stage(isShown: true)
            let painted = PaintedHarness(Toggled(stage: stage, transition: HalfFaded()))
            let alpha = Int(painted.alpha(25, 25))
            #expect(abs(alpha - 128) <= 2)
        }

        @Test func aLeavingViewKeepsItsPlaceUnderTheOnesOverIt() async {
            let stage = Stage(items: [0, 1])
            let painted = PaintedHarness(StackedCards(stage: stage))
            let blue = painted.pixel(25, 25)
            #expect(blue.z == 255 && blue.x == 0)

            withAnimation(.linear(duration: 10)) { stage.remove(0) }
            painted.update()
            await painted.settle(0.05)
            // The red one leaving under the blue one: blue still on top.
            #expect(painted.pixel(25, 25) == blue)
        }

        @Test func aLeavingViewStaysUnderTheOneReplacingIt() async {
            let stage = Stage(items: [0])
            let painted = PaintedHarness(SwappedSquare(stage: stage))

            withAnimation(.linear(duration: 0.1)) { stage.replace(with: 1) }
            painted.update()
            // The red one's exit plays out in this frame; the container is
            // not built again until the next change.
            await painted.settle(0.3)
            let blue = painted.pixel(25, 25)
            #expect(blue.z == 255 && blue.x == 0)

            withAnimation(.linear(duration: 10)) { stage.replace(with: 2) }
            painted.update()
            // Blue leaving, still all there, under green arriving at once.
            let green = painted.pixel(25, 25)
            #expect(green.y > 150 && green.z < 150)
        }

        // MARK: Where it is

        @Test func aLeavingViewIsNotHit() async {
            let log = Log()
            let stage = Stage(isShown: true)
            let harness = Harness(Covered(stage: stage, log: log))
            await harness.tap(Point(x: 25, y: 25))
            #expect(log.take() == ["front"])

            withAnimation(.linear(duration: 10)) { stage.hide() }
            harness.host.update()
            await harness.tap(Point(x: 25, y: 25))
            #expect(log.take() == ["back"])
        }

        @Test func anArrivingViewIsHitAtOnce() async {
            let log = Log()
            let stage = Stage()
            let harness = Harness(Covered(stage: stage, log: log))
            withAnimation(.linear(duration: 10)) { stage.show() }
            harness.host.update()
            await harness.tap(Point(x: 25, y: 25))
            #expect(log.take() == ["front"])
        }

        @Test func aMoveTransitionMovesTheViewByItsOwnSize() async {
            let log = Log()
            let stage = Stage()
            let harness = Harness(MovingReader(stage: stage, log: log, transition: .move(edge: .leading)))
            _ = log.take()

            withAnimation(.linear(duration: 0.1)) { stage.show() }
            harness.host.update()
            for _ in 0..<10 { await harness.settle(0.02) }
            let reported = log.take()
            // 100 across, starting one of its 50-point widths to the left.
            #expect(reported.first == "at 50")
            #expect(reported.count > 2)
            #expect(reported.last == "at 100")
        }

        @Test func aPushArrivesFromItsEdge() async {
            let log = Log()
            let stage = Stage()
            let harness = Harness(MovingReader(stage: stage, log: log, transition: .push(from: .trailing)))
            _ = log.take()

            withAnimation(.linear(duration: 0.1)) { stage.show() }
            harness.host.update()
            for _ in 0..<10 { await harness.settle(0.02) }
            let reported = log.take()
            #expect(reported.first == "at 150")
            #expect(reported.last == "at 100")
        }

        @Test func anOffsetMovesWhereTheViewIsHitAndAnimates() async {
            let log = Log()
            let stage = Stage()
            let harness = Harness(Shifted(stage: stage, log: log))
            await harness.tap(Point(x: 25, y: 25))
            #expect(log.take() == ["tap"])

            withAnimation(.linear(duration: 0.2)) { stage.show() }
            harness.host.update()
            // At the start of the move it is still where it was.
            await harness.tap(Point(x: 25, y: 25))
            #expect(log.take() == ["tap"])
            for _ in 0..<15 { await harness.settle(0.02) }
            await harness.tap(Point(x: 125, y: 25))
            #expect(log.take() == ["tap"])
            await harness.tap(Point(x: 25, y: 25))
            #expect(log.take() == [])
        }

        @Test func aGridRowArrivingKeepsItsColumns() async {
            let log = Log()
            let stage = Stage(items: [0])
            let harness = Harness(GridOfRows(stage: stage, log: log))

            withAnimation(.linear(duration: 10)) { stage.add(1) }
            harness.host.update()
            // The second row's second cell is in the second column — past
            // the first row's 100-point first cell — even while it fades in.
            await harness.tap(Point(x: 110, y: 30))
            #expect(log.take() == ["cell 1"])
            await harness.tap(Point(x: 30, y: 30))
            #expect(log.take() == [])
        }

        // MARK: The types

        @Test func phasesHaveTheirValues() {
            #expect(TransitionPhase.willAppear.value == -1)
            #expect(TransitionPhase.identity.value == 0)
            #expect(TransitionPhase.didDisappear.value == 1)
            #expect(TransitionPhase.identity.isIdentity)
            #expect(!TransitionPhase.willAppear.isIdentity)
            #expect(!TransitionPhase.didDisappear.isIdentity)
        }

        @Test func propertiesSayWhetherATransitionMoves() {
            #expect(!OpacityTransition.properties.hasMotion)
            #expect(!IdentityTransition.properties.hasMotion)
            #expect(MoveTransition.properties.hasMotion)
            #expect(ScaleTransition.properties.hasMotion)
            #expect(RotatingFadeTransition.properties.hasMotion)
            #expect(AsymmetricTransition<OpacityTransition, OpacityTransition>.properties.hasMotion == false)
            #expect(AsymmetricTransition<OpacityTransition, SlideTransition>.properties.hasMotion)
        }

        @Test func erasedTransitionsCompareByWhatTheyHold() {
            #expect(AnyTransition.opacity._isEquivalent(to: .opacity))
            #expect(AnyTransition(OpacityTransition())._isEquivalent(to: AnyTransition(OpacityTransition())))
            #expect(AnyTransition.scale(scale: 0.5)._isEquivalent(to: .scale(scale: 0.5)))
            #expect(!AnyTransition.scale(scale: 0.5)._isEquivalent(to: .scale(scale: 0.6)))
            #expect(!AnyTransition.opacity._isEquivalent(to: .slide))
            #expect(AnyTransition.move(edge: .top).combined(with: .opacity)
                ._isEquivalent(to: AnyTransition.move(edge: .top).combined(with: .opacity)))
            #expect(!AnyTransition.move(edge: .top).combined(with: .opacity)
                ._isEquivalent(to: AnyTransition.move(edge: .bottom).combined(with: .opacity)))
            #expect(AnyTransition.asymmetric(insertion: .slide, removal: .opacity)
                ._isEquivalent(to: .asymmetric(insertion: .slide, removal: .opacity)))
        }

        @Test func anErasedIdentityHasNothingToBuild() {
            #expect(AnyTransition.identity.box.isIdentity)
            #expect(AnyTransition(IdentityTransition()).box.isIdentity)
            #expect(!AnyTransition.opacity.box.isIdentity)
            #expect(!AnyTransition(RotatingFadeTransition()).box.isIdentity)
        }

        @Test func theFrameworksTransitionsLeaveTheViewAloneAtIdentity() {
            #expect(AnyTransition.opacity.box.leavesViewUnchangedAtIdentity)
            #expect(AnyTransition.slide.combined(with: .scale).box.leavesViewUnchangedAtIdentity)
            #expect(AnyTransition(OpacityTransition().animation(.default)).box.leavesViewUnchangedAtIdentity)
            // A transition of your own is taken at its word in identity.
            #expect(!AnyTransition(RotatingFadeTransition()).box.leavesViewUnchangedAtIdentity)
            #expect(!AnyTransition.opacity.combined(with: AnyTransition(HalfFaded())).box.leavesViewUnchangedAtIdentity)
        }

        @Test func anAttachedAnimationIsKnownWithoutBuilding() {
            #expect(!AnyTransition.opacity.box.animatesArrival)
            #expect(AnyTransition.opacity.animation(.default).box.animatesArrival)
            #expect(AnyTransition(OpacityTransition().animation(.default)).box.animatesRemoval)
            let asymmetric = AnyTransition.asymmetric(insertion: .opacity.animation(.default), removal: .slide)
            #expect(asymmetric.box.animatesArrival)
            #expect(!asymmetric.box.animatesRemoval)
        }
    }
}
