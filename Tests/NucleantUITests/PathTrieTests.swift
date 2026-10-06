//
//  PathTrieTests.swift
//  NucleantUITests
//
//  The builder's path trie: a node's children behave as a dictionary by
//  path component — below the size where they are only scanned, above it
//  where they are indexed too, and across removals that move the last child
//  into the gap — and the trie files, finds, detaches and re-attaches
//  subtrees by path.
//

import Testing
@testable import NucleantUI

@Suite
struct PathTrieTests {

    typealias Trie = PathTrie<Int>

    /// A node's children as a dictionary, read through every way in.
    static func contents(_ parent: Trie.Node, keys: some Sequence<Int>) -> [Int: ObjectIdentifier] {
        var result: [Int: ObjectIdentifier] = [:]
        parent.forEachChild { key, node in
            #expect(result[key] == nil, "key \(key) twice")
            result[key] = ObjectIdentifier(node)
        }
        #expect(parent.childCount == result.count)
        for key in keys {
            let found = parent.child(key).map(ObjectIdentifier.init)
            let unretained = parent.unretainedChild(key).map { ObjectIdentifier($0.takeUnretainedValue()) }
            #expect(found == result[key], "child, key \(key)")
            #expect(unretained == result[key], "unretainedChild, key \(key)")
        }
        return result
    }

    @Test
    func childrenBehaveAsADictionaryAtEverySize() {
        var generator = SystemRandomNumberGenerator()
        for round in 0..<40 {
            let parent = Trie.Node()
            var model: [Int: Trie.Node] = [:]
            // Small key ranges for collisions; hash-sized keys as a `List`
            // or `OutlineGroup` path component would be.
            let keyRange = round % 2 == 0 ? Array(0..<48) : (0..<48).map { $0 &* 0x1E37_79B9_7F4A_7C15 &- 0x3000_0000_0000_0000 }
            for _ in 0..<400 {
                let key = keyRange.randomElement(using: &generator)!
                switch Int.random(in: 0..<10, using: &generator) {
                case 0..<6:
                    let node = Trie.Node()
                    parent.setChild(node, at: key)
                    model[key] = node
                case 6..<9:
                    let removed = parent.removeChild(at: key)
                    #expect(removed.map(ObjectIdentifier.init) == model.removeValue(forKey: key).map(ObjectIdentifier.init))
                default:
                    if Int.random(in: 0..<20, using: &generator) == 0 {
                        parent.removeAllChildren()
                        model.removeAll()
                    }
                }
            }
            #expect(Self.contents(parent, keys: keyRange) == model.mapValues(ObjectIdentifier.init))

            let copy = Trie.Node()
            copy.setChildren(from: parent)
            #expect(Self.contents(copy, keys: keyRange) == model.mapValues(ObjectIdentifier.init))
        }
    }

    /// The trie holds what it was given, and lets it go when it's removed —
    /// whether the node was filed directly, replaced, or held by a subtree.
    @Test
    func childrenAreHeldAndReleased() {
        weak var dropped: Trie.Node?
        weak var replaced: Trie.Node?
        weak var nested: Trie.Node?
        let parent = Trie.Node()
        do {
            let first = Trie.Node()
            let second = Trie.Node()
            let deep = Trie.Node()
            second.setChild(deep, at: 1)
            dropped = first
            replaced = second
            nested = deep
            parent.setChild(first, at: 0)
            parent.setChild(second, at: 7)
        }
        #expect(dropped != nil && replaced != nil && nested != nil)
        parent.removeChild(at: 0)
        #expect(dropped == nil)
        parent.setChild(Trie.Node(), at: 7)
        #expect(replaced == nil)
        #expect(nested == nil)
    }

    @Test
    func filesFindsDetachesAndAttachesByPath() {
        let trie = Trie()
        trie.set(1, at: [0])
        trie.set(2, at: [0, 3])
        trie.set(3, at: [0, 3, 7])
        for index in 0..<40 { trie.set(100 + index, at: [0, 5, index]) }

        #expect(trie.value(at: [0]) == 1)
        #expect(trie.value(at: [0, 3, 7]) == 3)
        #expect(trie.value(at: [0, 5, 39]) == 139)
        #expect(trie.value(at: [0, 5]) == nil)
        #expect(trie.node(at: [0, 5]) != nil)
        #expect(trie.node(at: [0, 4]) == nil)
        #expect(trie.node(at: [0, 3, 7, 1]) == nil)
        #expect(trie.node(at: [0, 3, 7].prefix(2))?.value == 2)

        let wide = trie.detach(at: [0, 5])
        #expect(wide != nil)
        #expect(trie.node(at: [0, 5]) == nil)
        #expect(trie.value(at: [0, 3]) == 2)
        #expect(PathTrie.descend(from: wide!, along: [12])?.value == 112)

        trie.attach(wide!, at: [0, 9])
        #expect(trie.value(at: [0, 9, 0]) == 100)
        #expect(trie.value(at: [0, 9, 39]) == 139)

        var collected: [([Int], Int)] = []
        trie.root.collect(base: [], into: &collected)
        #expect(collected.count == 43)
        #expect(Set(collected.map(\.0)) == Set([[0], [0, 3], [0, 3, 7]] + (0..<40).map { [0, 9, $0] }))

        let all = trie.detach(at: [])
        #expect(trie.node(at: [0]) == nil)
        #expect(all.flatMap { PathTrie.descend(from: $0, along: [0, 3, 7]) }?.value == 3)
    }
}
