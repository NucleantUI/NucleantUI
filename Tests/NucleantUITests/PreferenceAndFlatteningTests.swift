//
//  PreferenceAndFlatteningTests.swift
//  NucleantUITests
//
//  How a subtree's children reach the layout and the preferences above it:
//  a `Group` dissolves into its container — its views are the stack's own
//  siblings — and a modifier on one wraps its first view; preferences reduce
//  across siblings and through groups, writers replace and transforms edit
//  what flows up, and a view on its way out no longer counts.
//

import Testing
@testable import NucleantUI

struct SumKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value += nextValue() }
}

/// Writers side by side, two of them in a group, one under a transform.
@View
struct PreferenceSum {
    let log: Log

    var body: some View {
        HStack(spacing: 0) {
            Color.red.frame(width: 10, height: 10).preference(key: SumKey.self, value: 1)
            Group {
                Color.red.frame(width: 10, height: 10).preference(key: SumKey.self, value: 10)
                Color.red.frame(width: 10, height: 10).preference(key: SumKey.self, value: 100)
            }
            Color.red.frame(width: 10, height: 10)
                .preference(key: SumKey.self, value: 1000)
                .transformPreference(SumKey.self) { $0 += 5000 }
        }
        .onPreferenceChange(SumKey.self) { log("sum \($0)") }
    }
}

/// A tap takes the second writer out, under an animation long enough that
/// it is still exiting when the value is read.
@View
struct LeavingWriter {
    let log: Log
    @State private var showsSecond = true

    var body: some View {
        VStack(spacing: 0) {
            Color.red
                .frame(width: 50, height: 50)
                .preference(key: SumKey.self, value: 1)
                .onTapGesture {
                    log("tap")
                    withAnimation(.linear(duration: 10)) { showsSecond = false }
                }
            if showsSecond {
                Color.blue
                    .frame(width: 50, height: 50)
                    .preference(key: SumKey.self, value: 2)
                    .transition(.opacity)
            }
        }
        .onPreferenceChange(SumKey.self) { log("sum \($0)") }
    }
}

/// Four 20-point squares in a row, the middle two in a group.
@View
struct GroupInStack {
    let log: Log

    var body: some View {
        HStack(spacing: 0) {
            Color.red.frame(width: 20, height: 20).onTapGesture { log("a") }
            Group {
                Color.red.frame(width: 20, height: 20).onTapGesture { log("b") }
                Color.red.frame(width: 20, height: 20).onTapGesture { log("c") }
            }
            Color.red.frame(width: 20, height: 20).onTapGesture { log("d") }
        }
    }
}

/// Padding on a group of two: it wraps the first.
@View
struct PaddedGroup {
    let log: Log

    var body: some View {
        Group {
            Color.red.frame(width: 20, height: 20).onTapGesture { log("first") }
            Color.blue.frame(width: 20, height: 20).onTapGesture { log("second") }
        }
        .padding(30)
    }
}

extension HostedViews {
    @MainActor
    @Suite
    struct PreferenceAndFlatteningTests {

        @Test func preferencesReduceAcrossSiblingsGroupsAndTransforms() {
            let log = Log()
            _ = Harness(PreferenceSum(log: log))
            #expect(log.take().last == "sum 6111")
        }

        @Test func aViewOnItsWayOutNoLongerCounts() async {
            let log = Log()
            let harness = Harness(LeavingWriter(log: log))
            #expect(log.take().last == "sum 3")
            // The column is centered across and starts at the top: the red
            // square is 75…125 by 0…50.
            await harness.tap(Point(x: 100, y: 25))
            #expect(log.take() == ["tap", "sum 1"])
        }

        @Test func aGroupsViewsAreTheStacksOwnSiblings() async {
            let log = Log()
            let harness = Harness(GroupInStack(log: log))
            // 80 wide at the leading edge, centered vertically.
            for x in [10.0, 30, 50, 70] {
                await harness.tap(Point(x: x, y: 100))
            }
            #expect(log.take() == ["a", "b", "c", "d"])
        }

        @Test func aModifierOnAGroupWrapsItsFirstView() async {
            let log = Log()
            let harness = Harness(PaddedGroup(log: log))
            await harness.tap(center)
            #expect(log.take() == ["first"])
        }
    }
}
