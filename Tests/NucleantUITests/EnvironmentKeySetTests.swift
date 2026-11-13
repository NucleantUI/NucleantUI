//
//  EnvironmentKeySetTests.swift
//  NucleantUITests
//
//  The environment keys a subtree read, as bits: what is noted, what a
//  record keeps, what a parent's frame takes in, and the keys a check of
//  whether a kept view still agrees goes through.
//

import Testing
@testable import NucleantUI

@Suite
struct EnvironmentKeySetTests {

    private func set(_ indices: [Int]) -> EnvironmentKeySet {
        var set = EnvironmentKeySet()
        for index in indices { set.insert(index) }
        return set
    }

    private func indices(of set: EnvironmentKeySet) -> [Int] {
        var found: [Int] = []
        _ = set.allIndices { found.append($0); return true }
        return found
    }

    @Test func bitsInBothWordsAreKeptAndListedInOrder() {
        let keys = set([70, 0, 63, 64, 127, 5])
        #expect(indices(of: keys) == [0, 5, 63, 64, 70, 127])
        #expect(!keys.isEmpty)
        #expect(EnvironmentKeySet().isEmpty)
    }

    @Test func aUnionHoldsBoth() {
        var keys = set([1, 100])
        keys.formUnion(set([2, 100, 65]))
        #expect(indices(of: keys) == [1, 2, 65, 100])
        #expect(set([2, 65]).isSubset(of: keys))
        #expect(!set([2, 66]).isSubset(of: keys))
        #expect(EnvironmentKeySet().isSubset(of: keys))
    }

    @Test func goingThroughStopsAtTheFirstThatFails() {
        var seen: [Int] = []
        let allPassed = set([3, 9, 80]).allIndices { index in
            seen.append(index)
            return index < 9
        }
        #expect(!allPassed)
        #expect(seen == [3, 9])
    }
}
