//
//  EnvironmentValuesTests.swift
//  NucleantUITests
//
//  Environment values as a chain of typed writes: what a read finds, what
//  a write leaves of the environment it was made in, which values two
//  environments differ in, and an environment moved from one parent to
//  another.
//

import Testing
@testable import NucleantUI

private struct DepthKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct LabelKey: EnvironmentKey {
    static let defaultValue = "none"
}

/// A class: the same object is the same value, another object is not.
@MainActor
private final class Marker {}

private struct MarkerKey: EnvironmentKey {
    static let defaultValue: Marker? = nil
}

extension EnvironmentValues {
    fileprivate var depth: Int {
        get { self[DepthKey.self] }
        set { self[DepthKey.self] = newValue }
    }

    fileprivate var label: String {
        get { self[LabelKey.self] }
        set { self[LabelKey.self] = newValue }
    }

    fileprivate var marker: Marker? {
        get { self[MarkerKey.self] }
        set { self[MarkerKey.self] = newValue }
    }
}

@MainActor
@Suite
struct EnvironmentValuesTests {

    private func keys(_ types: [Any.Type]) -> EnvironmentKeySet {
        var set = EnvironmentKeySet()
        for type in types {
            set.insert(EnvironmentReads.shared.index(of: ObjectIdentifier(type)))
        }
        return set
    }

    @Test func aReadFindsTheNewestWriteOrTheDefault() {
        var environment = EnvironmentValues()
        #expect(environment.depth == 0)
        #expect(environment.label == "none")
        environment.depth = 1
        environment.label = "a"
        environment.depth = 2
        #expect(environment.depth == 2)
        #expect(environment.label == "a")
        #expect(environment.marker == nil)
    }

    @Test func aWriteLeavesTheEnvironmentItWasMadeIn() {
        var parent = EnvironmentValues()
        parent.depth = 1
        var child = parent
        child.depth = 2
        child.label = "child"
        #expect(parent.depth == 1)
        #expect(parent.label == "none")
        #expect(child.depth == 2)
        // The child holds the parent's writes as its own tail.
        #expect(child.head?.next?.next === parent.head)
    }

    @Test func theSameValuesWrittenAgainDoNotDiffer() {
        var root = EnvironmentValues()
        root.label = "root"
        var a = root
        a.depth = 3
        var b = root
        b.depth = 3
        #expect(a.version != b.version)
        #expect(!a.differs(from: b))
        #expect(a.agrees(with: b, on: keys([DepthKey.self, LabelKey.self])))
    }

    @Test func aChangedValueDiffersOnlyForTheViewsThatReadIt() {
        var root = EnvironmentValues()
        root.label = "root"
        var a = root
        a.depth = 3
        var b = root
        b.depth = 4
        #expect(a.differs(from: b))
        #expect(!a.agrees(with: b, on: keys([DepthKey.self])))
        #expect(a.agrees(with: b, on: keys([LabelKey.self])))
        #expect(a.agrees(with: b, on: EnvironmentKeySet()))
    }

    @Test func aValueWrittenInOneAndNotTheOtherDiffers() {
        let root = EnvironmentValues()
        var a = root
        a.depth = 0
        #expect(a.differs(from: root))
        #expect(root.differs(from: a))
        #expect(!a.agrees(with: root, on: keys([DepthKey.self])))
    }

    @Test func anObjectIsTheSameValueOnlyAsItself() {
        let marker = Marker()
        var a = EnvironmentValues()
        a.marker = marker
        var b = EnvironmentValues()
        b.marker = marker
        #expect(!a.differs(from: b))
        b.marker = Marker()
        #expect(a.differs(from: b))
    }

    @Test func aRebasedEnvironmentKeepsItsOwnWritesOverTheNewParent() {
        var old = EnvironmentValues()
        old.label = "old"
        old.depth = 1
        var child = old
        child.depth = 2
        var grandchild = child
        grandchild.marker = Marker()

        var new = EnvironmentValues()
        new.label = "new"
        new.depth = 7

        var relinked: [ObjectIdentifier: (from: EnvironmentEntry, to: EnvironmentEntry)] = [:]
        let movedChild = child.rebased(from: old, to: new, relinked: &relinked)
        let movedGrandchild = grandchild.rebased(from: old, to: new, relinked: &relinked)
        #expect(movedChild.label == "new")
        #expect(movedChild.depth == 2)
        #expect(movedGrandchild.label == "new")
        #expect(movedGrandchild.depth == 2)
        #expect(movedGrandchild.marker === grandchild.marker)
        // The grandchild's chain runs through the child's, as it did.
        #expect(movedGrandchild.head?.next === movedChild.head)
        #expect(movedChild.head?.next === new.head)
        // A moved write is the same value it was.
        #expect(!movedChild.agrees(with: child, on: keys([LabelKey.self])))
        #expect(movedChild.agrees(with: child, on: keys([DepthKey.self])))
        #expect(movedChild.version != child.version)
        // The environment of the view that moved is the new one.
        #expect(old.rebased(from: old, to: new, relinked: &relinked).version == new.version)
    }

    @Test func anEnvironmentNotDerivedFromTheOldParentTakesItsChangesKeyByKey() {
        var old = EnvironmentValues()
        old.label = "old"
        old.depth = 1
        var new = EnvironmentValues()
        new.label = "new"
        // Holds old's depth by value, and a label of its own.
        var other = EnvironmentValues()
        other.depth = 1
        other.label = "own"
        var sameDepth = other
        sameDepth.marker = Marker()

        var relinked: [ObjectIdentifier: (from: EnvironmentEntry, to: EnvironmentEntry)] = [:]
        let moved = sameDepth.rebased(from: old, to: new, relinked: &relinked)
        // Neither held as old holds it — not the same write — so kept.
        #expect(moved.label == "own")
        #expect(moved.depth == 1)
        #expect(moved.marker === sameDepth.marker)

        // One that holds old's very writes takes new's, or the default
        // where new wrote none. Written over enough times, its chain is
        // folded into one of its own, which holds old's writes as copies.
        var copy = old
        let marker = Marker()
        for _ in 0..<70 { copy.marker = marker }
        #expect(!chain(of: copy, contains: old.head))
        let movedCopy = copy.rebased(from: old, to: new, relinked: &relinked)
        #expect(movedCopy.label == "new")
        #expect(movedCopy.depth == 0)
        #expect(movedCopy.marker === copy.marker)
    }

    @Test func aValueWrittenOverAndOverDoesNotGrowTheChain() {
        var environment = EnvironmentValues()
        environment.label = "kept"
        for depth in 1...500 {
            environment.depth = depth
        }
        #expect(environment.depth == 500)
        #expect(environment.label == "kept")
        #expect((environment.head?.depth ?? 0) <= 65)
    }
}

private func chain(of environment: EnvironmentValues, contains entry: EnvironmentEntry?) -> Bool {
    var current = environment.head
    while let found = current {
        if found === entry { return true }
        current = found.next
    }
    return false
}
