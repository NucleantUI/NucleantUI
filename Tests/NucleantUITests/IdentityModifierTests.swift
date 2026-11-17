//
//  IdentityModifierTests.swift
//  NucleantUITests
//
//  `.id(_:)`: a view whose identity is a value — a new value is a new view
//  with state of its own.
//

import Foundation
import Testing
@testable import NucleantUI

/// A counter whose identity is `version`.
@View
struct VersionedCounter {
    let version: Int
    let log: Log

    var body: some View {
        IdentifiedCounter(log: log).id(version)
    }
}

@View
struct IdentifiedCounter {
    let log: Log
    @State private var count = 0

    var body: some View {
        Button("count") {
            count += 1
            log("count \(count)")
        }
        .frame(width: 200, height: 200)
    }
}

/// The counter over three buttons: the next version, the one before, and
/// a change that rebuilds the counter with the same version.
@View
struct VersionedCounterHost {
    let log: Log
    @State private var version = 0
    @State private var touches = 0

    var body: some View {
        VStack(spacing: 0) {
            VersionedCounter(version: version, log: log)
            HStack(spacing: 0) {
                Button("next") { version += 1 }
                    .frame(width: 66, height: 40)
                Button("previous") { version -= 1 }
                    .frame(width: 66, height: 40)
                Button("touch \(touches)") { touches += 1 }
                    .frame(width: 68, height: 40)
            }
        }
    }
}

extension HostedViews {
    @MainActor
    @Suite struct IdentityModifier {

        private static let counter = Point(x: 100, y: 100)
        private static let next = Point(x: 33, y: 220)
        private static let previous = Point(x: 99, y: 220)
        private static let touch = Point(x: 166, y: 220)

        private func makeHarness(_ log: Log) -> Harness {
            Harness(VersionedCounterHost(log: log), size: Size(width: 200, height: 240))
        }

        @Test func aNewIDIsANewViewWithItsOwnState() async {
            let log = Log()
            let harness = makeHarness(log)
            await harness.tap(Self.counter)
            await harness.tap(Self.counter)
            #expect(log.take() == ["count 1", "count 2"])

            await harness.tap(Self.next)
            await harness.frames(30)
            await harness.tap(Self.counter)
            #expect(log.take() == ["count 1"])
        }

        @Test func theSameIDAcrossRebuildsKeepsTheState() async {
            let log = Log()
            let harness = makeHarness(log)
            await harness.tap(Self.counter)
            await harness.tap(Self.touch)
            await harness.tap(Self.counter)
            #expect(log.take() == ["count 1", "count 2"])
        }

        @Test func backToAnEarlierIDIsANewViewToo() async {
            let log = Log()
            let harness = makeHarness(log)
            await harness.tap(Self.counter)
            await harness.tap(Self.counter)
            await harness.tap(Self.next)
            await harness.frames(30)
            await harness.tap(Self.previous)
            await harness.frames(30)
            _ = log.take()

            await harness.tap(Self.counter)
            #expect(log.take() == ["count 1"], "the view of the first id left; its state went with it")
        }
    }
}
