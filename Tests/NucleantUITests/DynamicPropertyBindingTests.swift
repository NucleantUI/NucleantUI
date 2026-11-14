//
//  DynamicPropertyBindingTests.swift
//  NucleantUITests
//
//  The builder binds the copy of a view it builds, in place: `@Environment`,
//  `@Namespace` and `@FocusState` keep what they were bound to in their own
//  fields, and what `body` hands out — an action, a projection — is made from
//  that copy, so it sees those values, the latest build's.
//

import Testing
@testable import NucleantUI

private struct ShadeKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    fileprivate var shade: Int {
        get { self[ShadeKey.self] }
        set { self[ShadeKey.self] = newValue }
    }
}

/// Puts `shade` into the environment; the top half raises it.
@View
private struct ShadeParent {
    let log: Log
    @State private var shade = 1

    var body: some View {
        VStack(spacing: 0) {
            Color.gray
                .frame(width: 200, height: 100)
                .onTapGesture { shade += 1 }
            ShadeReader(log: log)
        }
        .environment(\.shade, shade)
    }
}

/// Logs, when tapped, what its wrappers hold — from the action its body made.
@View
private struct ShadeReader {
    let log: Log
    @Environment(\.shade) private var shade
    @Namespace private var space
    @FocusState private var focused: Bool

    var body: some View {
        Color.blue
            .frame(width: 200, height: 100)
            .onTapGesture {
                log("shade \(shade) focused \(focused) space \(space == space)")
            }
    }
}

extension HostedViews {

    @MainActor
    @Suite
    struct BoundInPlace {

        @Test func anActionSeesTheValuesItsBuildWasBoundTo() async {
            let log = Log()
            let harness = Harness(ShadeParent(log: log))
            await harness.tap(Point(x: 100, y: 150))
            #expect(log.take() == ["shade 1 focused false space true"])
            await harness.tap(Point(x: 100, y: 50))     // shade 2: the reader is built again
            await harness.tap(Point(x: 100, y: 150))
            #expect(log.take() == ["shade 2 focused false space true"])
        }
    }
}

@MainActor
@Suite
struct DynamicPropertyBindingTests {

    /// Property 0 of a view standing at a position of its own.
    private func context(_ environment: EnvironmentValues) -> BindingContext {
        BindingContext(
            position: ViewPosition(parent: nil, key: 0),
            index: 0,
            owner: ViewIdentity(type: ObjectIdentifier(Int.self), viewID: .unknown),
            environment: environment
        )
    }

    @Test func anEnvironmentPropertyHoldsTheValueItIsBoundTo() {
        var environment = EnvironmentValues()
        environment.shade = 7
        var property = Environment(\.shade)
        property._bind(to: context(environment))
        #expect(property.wrappedValue == 7)
    }

    @Test func aNamespaceKeepsItsIDAcrossBindings() {
        let context = context(EnvironmentValues())
        var first = Namespace()
        first._bind(to: context)
        var second = Namespace()
        second._bind(to: context)
        #expect(first.wrappedValue == second.wrappedValue)
    }
}
