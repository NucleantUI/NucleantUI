//
//  ViewMacroTests.swift
//  NucleantUIMacrosTests
//
//  The init `@View` generates: which stored properties become parameters.
//  A wrapper that makes itself — from its arguments or its `init()` — is
//  not one; `@Bindable` takes its object.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import NucleantUIMacros

private let macros: [String: Macro.Type] = [
    "View": ViewMacro.self,
]

final class ViewMacroTests: XCTestCase {

    func testSelfMadeWrappersAreNoParameters() {
        assertMacroExpansion(
            """
            @View
            struct Shelf {
                @Query(#Predicate<Item> { $0.isOpen }) private var open: [Item]
                @Query private var all: [Item]
                @Bindable var library: Library
                let title: String
            }
            """,
            expandedSource: """
            struct Shelf {
                @Query(#Predicate<Item> { $0.isOpen }) private var open: [Item]
                @Query private var all: [Item]
                @Bindable var library: Library
                let title: String

                var _viewID: ViewID = .unknown

                @MainActor func _isEquivalent(to other: Self) -> Bool {
                    _areEquivalent(self._open, other._open)
                            && _areEquivalent(self._all, other._all)
                            && _areEquivalent(self._library, other._library)
                            && _areEquivalent(self.title, other.title)
                }

                @MainActor mutating func _bindDynamicProperties(_ binder: DynamicPropertyBinder) {
                    binder.bind(&self._open, index: 0)
                    binder.bind(&self._all, index: 1)
                    binder.bind(&self._library, index: 2)
                }

                @MainActor init(
                    library: Library,
                    title: String,
                    _viewID: ViewID = #viewID
                ) {
                    self._library = Bindable(wrappedValue: library)
                    self.title = title
                    self._viewID = _viewID
                }
            }
            """,
            macros: macros
        )
    }
}
