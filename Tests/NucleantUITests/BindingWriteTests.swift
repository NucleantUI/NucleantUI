//
//  BindingWriteTests.swift
//  NucleantUITests
//
//  A write through a binding projected from state: only the part written
//  is compared and written, the readers it reaches are found by the first
//  key path they read through, and a write into an object leaves the slot
//  as it was.
//

import Testing
@testable import NucleantUI

private struct Track: Equatable {
    var level: Int
    var name: String
}

@MainActor
private final class Model {
    var name = "a"
}

// Writes go to the process-wide invalidation queue, which the hosted views
// share: these run among them, one at a time.
extension HostedViews {

    @MainActor
    @Suite
    struct BindingWriteTests {

        /// Views standing at `[n]`, to list as readers.
        private let tree = RebuildRecords()

        private func reader(_ slot: Int) -> PositionHandle {
            tree.position(along: [slot]).handle
        }

        /// A binding onto a slot holding `value`, as `$state` makes one.
        private func bound<Value>(_ value: Value) -> (StateStorage<Value>, Binding<Value>) {
            let storage = StateStorage(value, owner: reader(0))
            let holder = _StateProperty<Value>.Holder()
            holder.storage = storage
            let binding = Binding(
                source: BindingSource(root: ObjectIdentifier(storage), keyPaths: []),
                location: StateRootLocation(holder: holder)
            )
            return (storage, binding)
        }

        private func dirtied() -> Set<[Int]> {
            Invalidator.shared.consume().paths
        }

        @Test func aWriteToOnePartComparesAndWritesThatPart() {
            let (storage, tracks) = bound([Track(level: 1, name: "a"), Track(level: 2, name: "b")])
            _ = dirtied()
            let level = tracks[1].level

            level.wrappedValue = 2              // what it holds: no write
            #expect(storage.version == 0)
            #expect(dirtied().isEmpty)

            level.wrappedValue = 5
            #expect(storage.version == 1)
            #expect(storage.peek() == [Track(level: 1, name: "a"), Track(level: 5, name: "b")])
            #expect(level.wrappedValue == 5)
            #expect(tracks[1].name.wrappedValue == "b")
        }

        @Test func aProjectionKeepsItsChainAsTheSource() {
            let (storage, tracks) = bound([Track(level: 1, name: "a")])
            let level = tracks[0].level
            #expect(level.source?.root == ObjectIdentifier(storage))
            #expect(level.source?.keyPaths == [\[Track].[0], \Track.level])
            #expect(level._isEquivalent(to: tracks[0].level))
            #expect(!level._isEquivalent(to: tracks[1].level))
        }

        @Test func aWriteReachesTheReadersOfItsPartAndOfTheWhole() {
            let (storage, tracks) = bound([Track(level: 1, name: "a"), Track(level: 2, name: "b")])
            storage.readers.add(reader(1), via: [])
            storage.readers.add(reader(2), via: [\[Track].[0], \Track.level])
            storage.readers.add(reader(3), via: [\[Track].[1], \Track.level])
            storage.readers.add(reader(4), via: [\[Track].[1]])
            storage.readers.add(reader(5), via: [\[Track].[1], \Track.name])
            _ = dirtied()

            tracks[1].level.wrappedValue = 9
            #expect(dirtied() == [[1], [3], [4]])

            tracks.wrappedValue = []
            #expect(dirtied() == [[1], [2], [3], [4], [5]])
        }

        @Test func aReaderTakenOutIsReachedNoMore() {
            let (storage, tracks) = bound([Track(level: 1, name: "a")])
            storage.readers.add(reader(1), via: [\[Track].[0], \Track.level])
            storage.readers.add(reader(1), via: [\[Track].[0], \Track.name])
            storage.readers.add(reader(1), via: [])
            storage.readers.add(reader(2), via: [\[Track].[0]])
            storage.readers.remove(reader(1))
            _ = dirtied()

            tracks[0].level.wrappedValue = 3
            #expect(dirtied() == [[2]])
            storage.readers.remove(reader(2))
            tracks.wrappedValue = []
            #expect(dirtied().isEmpty)
        }

        @Test func aWriteIntoAnObjectLeavesTheSlotAsItWas() {
            let model = Model()
            let (storage, binding) = bound(model)
            storage.readers.add(reader(1), via: [])
            _ = dirtied()

            binding.name.wrappedValue = "b"
            #expect(model.name == "b")
            #expect(storage.version == 0)
            #expect(dirtied().isEmpty)
        }

        @Test func aProjectionOfClosuresWritesTheWholeValueBack() {
            var held = Track(level: 1, name: "a")
            var writes = 0
            let binding = Binding(get: { held }, set: { held = $0; writes += 1 })
            let level = binding.level
            #expect(level.wrappedValue == 1)
            level.wrappedValue = 4
            #expect(held == Track(level: 4, name: "a"))
            #expect(writes == 1)
            #expect(level.source == nil)
        }
    }
}
