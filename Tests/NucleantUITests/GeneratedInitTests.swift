//
//  GeneratedInitTests.swift
//  NucleantUITests
//
//  Views whose stored properties carry wrappers that make themselves — from
//  the arguments they are written with, or from their `init()` — get an
//  init without them, with their types written out; and still bind them.
//  `@Bindable` stays a parameter.
//

import Observation
import Testing
@testable import NucleantUI

/// A wrapper of the kind a data library declares: no `init(wrappedValue:)`,
/// made from its arguments or with none, bound like any dynamic property.
@MainActor
@propertyWrapper
private struct CatalogueShelf: DynamicProperty {
    private let label: String
    private var boundTimes = 0

    init() { label = "all" }
    init(_ label: String) { self.label = label }

    var wrappedValue: [String] { [label, "bound \(boundTimes)"] }

    mutating func _bind(to context: BindingContext) {
        boundTimes += 1
    }
}

@MainActor
@Observable
private final class Library {
    var name = "Central"
}

@View
private struct Catalogue {
    @CatalogueShelf("fiction") private var fiction: [String]
    @CatalogueShelf private var everything: [String]
    @Bindable var library: Library
    let title: String
    let seen: CatalogueSeen

    var body: some View {
        Text(seen.record(title: title, library: library.name, fiction: fiction, everything: everything))
    }
}

@MainActor
private final class CatalogueSeen {
    var line: String?

    func record(title: String, library: String, fiction: [String], everything: [String]) -> String {
        let line = "\(title) at \(library): \(fiction.joined(separator: " ")) / \(everything.joined(separator: " "))"
        self.line = line
        return line
    }
}

@MainActor
struct GeneratedInitTests {

    @Test func selfMadeWrappersAreLeftOutOfTheInitAndStillBound() async {
        let seen = CatalogueSeen()
        let library = Library()
        // Only the Bindable and the plain property are parameters.
        let host = ViewHost(root: Catalogue(library: library, title: "Shelves", seen: seen))
        host.setSize(Size(width: 320, height: 200))
        host.update()

        #expect(seen.line == "Shelves at Central: fiction bound 1 / all bound 1")

        // The Bindable is the caller's object, observed as ever.
        library.name = "Branch"
        for _ in 0..<100 where seen.line?.contains("Branch") != true {
            host.update()
            await Task.yield()
        }
        #expect(seen.line?.hasPrefix("Shelves at Branch:") == true)
    }
}
