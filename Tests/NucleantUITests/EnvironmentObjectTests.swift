//
//  EnvironmentObjectTests.swift
//  NucleantUITests
//
//  `@Environment(T.self)` and `.environment(_:)` with an `Observable`
//  object: read where it is set, the nearest one when set twice, nil when
//  not set or taken away.
//

import Observation
import Testing
@testable import NucleantUI

@MainActor @Observable
final class EnvironmentLibrary {
    var name: String
    init(name: String) { self.name = name }
}

/// What the readers saw.
@MainActor
final class LibraryProbe {
    var name: String?
    var found = false
}

@View
struct RequiredLibraryReader {
    let probe: LibraryProbe
    @Environment(EnvironmentLibrary.self) private var library

    var body: some View {
        let _ = probe.name = library.name
        Color.clear
    }
}

@View
struct OptionalLibraryReader {
    let probe: LibraryProbe
    @Environment(EnvironmentLibrary.self) private var library: EnvironmentLibrary?

    var body: some View {
        let _ = probe.name = library?.name
        Color.clear
    }
}

@View
struct SubscriptLibraryReader {
    let probe: LibraryProbe
    @Environment(\.self) private var environment

    var body: some View {
        let _ = probe.found = environment[EnvironmentLibrary.self] != nil
        Color.clear
    }
}

extension HostedViews {
    @MainActor
    @Suite struct EnvironmentObjects {

        @Test func anObjectIsReadWhereItIsSet() {
            let probe = LibraryProbe()
            _ = Harness(RequiredLibraryReader(probe: probe).environment(EnvironmentLibrary(name: "City")))
            #expect(probe.name == "City")
        }

        @Test func theNearestObjectWins() {
            let probe = LibraryProbe()
            _ = Harness(
                RequiredLibraryReader(probe: probe)
                    .environment(EnvironmentLibrary(name: "Inner"))
                    .environment(EnvironmentLibrary(name: "Outer"))
            )
            #expect(probe.name == "Inner")
        }

        @Test func anOptionalReadIsNilUntilSetAndAfterTakenAway() {
            let probe = LibraryProbe()
            _ = Harness(OptionalLibraryReader(probe: probe))
            #expect(probe.name == nil)

            _ = Harness(OptionalLibraryReader(probe: probe).environment(EnvironmentLibrary(name: "City")))
            #expect(probe.name == "City")

            _ = Harness(
                OptionalLibraryReader(probe: probe)
                    .environment(nil as EnvironmentLibrary?)
                    .environment(EnvironmentLibrary(name: "City"))
            )
            #expect(probe.name == nil)
        }

        @Test func theSubscriptReadsTheObject() {
            let probe = LibraryProbe()
            _ = Harness(SubscriptLibraryReader(probe: probe))
            #expect(!probe.found)

            _ = Harness(SubscriptLibraryReader(probe: probe).environment(EnvironmentLibrary(name: "City")))
            #expect(probe.found)
        }
    }
}
