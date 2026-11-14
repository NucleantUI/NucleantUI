//
//  ShapeStyleTests.swift
//  NucleantUITests
//
//  `ShapeStyle` as a protocol: each style a type of its own, resolved in the
//  environment of the view it paints — a style of an app's own through
//  `resolve(in:)`, the foreground and the tint from what is in effect — and
//  resolved again when what it read changes.
//

import Testing
@testable import NucleantUI

/// A style of an app's own: orange in dark mode, red in light.
private struct Warning: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? .orange : .red
    }
}

/// Notes each time it is resolved, and the scheme it was resolved under.
private struct Noting: ShapeStyle {
    let log: Log

    func resolve(in environment: EnvironmentValues) -> Color {
        let scheme = environment.colorScheme
        MainActor.assumeIsolated { log("resolve \(scheme)") }
        return .blue
    }
}

/// What a style paints — handed its style by its type, as the modifiers are.
private func paint<S: ShapeStyle>(_ style: S, in environment: EnvironmentValues = EnvironmentValues()) -> _ResolvedPaint {
    style.paint(in: environment)
}

@MainActor
@Suite
struct ShapeStyleTests {

    private func environment(_ scheme: ColorScheme) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return environment
    }

    @Test func aStyleOfAnAppsOwnIsWhatItResolvesTo() {
        #expect(paint(Warning(), in: environment(.light)) == .color(.red))
        #expect(paint(Warning(), in: environment(.dark)) == .color(.orange))
    }

    @Test func aColorNamedThroughTheProtocolIsTheColor() {
        #expect(paint(.red) == .color(Color.red))
        #expect(paint(.clear) == .color(Color.clear))
        #expect(paint(.clear).isClear)
    }

    @Test func theSemanticStylesFollowTheScheme() {
        let primary = HierarchicalShapeStyle.primary.colors
        #expect(paint(.primary, in: environment(.light)) == .color(primary.light))
        #expect(paint(.primary, in: environment(.dark)) == .color(primary.dark))
        #expect(paint(.secondary, in: environment(.dark)) != paint(.primary, in: environment(.dark)))
        #expect(paint(.background, in: environment(.dark)) == .color(BackgroundStyle().colors.dark))
        #expect(paint(.secondaryBackground, in: environment(.light)) == .color(.white))
        #expect(paint(.separator, in: environment(.light)) == .color(SeparatorShapeStyle.colors.light))
    }

    @Test func theForegroundIsTheOneInEffect() {
        var environment = environment(.dark)
        #expect(paint(.foreground, in: environment) == paint(.primary, in: environment))
        environment.foregroundStyle = AnyShapeStyle(Warning())
        #expect(paint(.foreground, in: environment) == .color(.orange))
        // Naming itself, it stands for the default.
        environment.foregroundStyle = AnyShapeStyle(.foreground)
        #expect(paint(.foreground, in: environment) == paint(.primary, in: environment))
    }

    @Test func theTintIsTheOneInEffect() {
        var environment = EnvironmentValues()
        #expect(paint(.tint, in: environment) == .color(.blue))
        environment.tint = AnyShapeStyle(Color.pink)
        #expect(paint(.tint, in: environment) == .color(.pink))
        environment.tint = AnyShapeStyle(.tint)
        #expect(paint(.tint, in: environment) == .color(.blue))
    }

    @Test func opacityFadesWhatAStyleResolvesTo() {
        #expect(paint(Warning().opacity(0.5), in: environment(.dark)) == .color(Color.orange.opacity(0.5)))
        #expect(paint(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom).opacity(1))
                == paint(LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)))
    }

    @Test func anErasedStyleIsTheSameInputAsTheStyleItHolds() {
        let red = AnyShapeStyle(Color.red)
        #expect(red._isEquivalent(to: AnyShapeStyle(Color.red)))
        #expect(!red._isEquivalent(to: AnyShapeStyle(Color.blue)))
        #expect(!AnyShapeStyle(HierarchicalShapeStyle.primary)._isEquivalent(to: AnyShapeStyle(BackgroundStyle())))
        #expect(AnyShapeStyle(red).box === red.box, "erasing an erased style keeps its box")
        #expect(paint(red) == .color(.red))
    }

    @Test func aGradientIsPaintedAsItIsLaidOut() {
        let gradient = Gradient(colors: [.red, .blue])
        #expect(paint(.linearGradient(gradient, startPoint: .leading, endPoint: .trailing))
                == _ResolvedPaint(.linearGradient(gradient, startPoint: .leading, endPoint: .trailing)))
        #expect(paint(.radialGradient(gradient, center: .center, startRadius: 0, endRadius: 10))
                == _ResolvedPaint(.radialGradient(gradient, center: .center, startRadius: 0, endRadius: 10)))
        #expect(paint(.linearGradient(colors: [.red, .blue])).flatColor == .red)
    }

    @Test func aShapeIsFilledWithWhatItsStyleResolvesTo() {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let list = OffscreenRender(environment: environment).list(
            of: Rectangle().fill(Warning()).frame(width: 10, height: 10),
            size: Size(width: 10, height: 10)
        )
        let fills = list.commands.compactMap { command -> _ResolvedPaint? in
            if case .shape(let draw) = command { return draw.fill }
            return nil
        }
        #expect(fills == [.color(.orange)])
    }
}

/// A square filled with a style that notes each time it is resolved, and a
/// counter beside it that only its own view reads.
@View
private struct NotedSquare {
    let log: Log

    var body: some View {
        let _ = log("body")
        VStack(spacing: 0) {
            Rectangle()
                .fill(Noting(log: log))
                .frame(width: 100, height: 100)
            Counter(log: log)
        }
    }
}

@View
private struct Counter {
    let log: Log
    @State private var taps = 0

    var body: some View {
        let _ = log("count \(taps)")
        Color.gray
            .frame(width: 100, height: 100)
            .onTapGesture { taps += 1 }
    }
}

extension HostedViews {

    @MainActor
    @Suite
    struct StylesResolvedWhereBuilt {

        @Test func aStyleIsResolvedAgainWhenTheSchemeChanges() async {
            let log = Log()
            let harness = Harness(NotedSquare(log: log))
            #expect(log.take() == ["body", "resolve light", "count 0"])
            // A change beside it leaves the shape as it is.
            await harness.tap(Point(x: 50, y: 150))
            #expect(log.take() == ["count 1"])
            // The scheme it read changed: resolved again, under the new one.
            harness.host.environment.colorScheme = .dark
            harness.host.invalidate()
            await harness.settle()
            #expect(log.take().contains("resolve dark"))
        }
    }
}
