//
//  StateMacroTests.swift
//  NucleantUIMacrosTests
//
//  What `@State` expands to: storage holding the initial value as a
//  closure, accessors through it, a projection — and what it refuses.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import NucleantUIMacros

private let macros: [String: Macro.Type] = [
    "State": StateMacro.self,
    "_StateProjectedValue": StateProjectedValueMacro.self,
]

final class StateMacroTests: XCTestCase {

    func testInferredType() {
        assertMacroExpansion(
            """
            struct V {
                @State private var model = Model()
            }
            """,
            expandedSource: """
            struct V {
                private var model {
                    get {
                        _model.wrappedValue
                    }
                    nonmutating set {
                        _model.wrappedValue = newValue
                    }
                }

                private var _model = _StateProperty({
                        Model()
                    })

                @MainActor private var $model {
                    get {
                        _model.projectedValue
                    }
                }
            }
            """,
            macros: macros
        )
    }

    func testDeclaredTypeAndAccess() {
        assertMacroExpansion(
            """
            struct V {
                @State public var count: Int = 0
            }
            """,
            expandedSource: """
            struct V {
                public var count: Int {
                    get {
                        _count.wrappedValue
                    }
                    nonmutating set {
                        _count.wrappedValue = newValue
                    }
                }

                private var _count = _StateProperty<Int>({
                        0
                    })

                @MainActor public var $count: Binding<Int> {
                    _count.projectedValue
                }
            }
            """,
            macros: macros
        )
    }

    func testNoInitialValue() {
        assertMacroExpansion(
            """
            struct V {
                @State var label: String
            }
            """,
            expandedSource: """
            struct V {
                var label: String {
                    @storageRestrictions(initializes: _label)
                    init(initialValue) {
                        _label = _StateProperty(initialValue: initialValue)
                    }
                    get {
                        _label.wrappedValue
                    }
                    nonmutating set {
                        _label.wrappedValue = newValue
                    }
                }

                private var _label: _StateProperty<String>

                @MainActor var $label: Binding<String> {
                    _label.projectedValue
                }
            }
            """,
            macros: macros
        )
    }

    func testOptionalStartsAtNil() {
        assertMacroExpansion(
            """
            struct V {
                @State private var picked: String?
            }
            """,
            expandedSource: """
            struct V {
                private var picked: String? {
                    get {
                        _picked.wrappedValue
                    }
                    nonmutating set {
                        _picked.wrappedValue = newValue
                    }
                }

                private var _picked = _StateProperty<String?>({
                        nil
                    })

                @MainActor private var $picked: Binding<String?> {
                    _picked.projectedValue
                }
            }
            """,
            macros: macros
        )
    }

    func testObservers() {
        assertMacroExpansion(
            """
            struct V {
                @State private var count = 0 {
                    willSet { print(newValue) }
                    didSet(previous) {
                        print(previous)
                    }
                }
            }
            """,
            expandedSource: """
            struct V {
                private var count {
                    willSet { print(newValue) }
                    didSet(previous) {
                        print(previous)
                    }
                    get {
                        _count.wrappedValue
                    }

                    nonmutating set {
                        let __macro_local_8oldValuefMu_ = _count.wrappedValue
                        ({ newValue in
                                print(newValue)
                            })(newValue)
                        _count.wrappedValue = newValue
                        ({ previous in
                                print(previous)
                            })(__macro_local_8oldValuefMu_)
                    }
                }

                private var _count = _StateProperty({
                        0
                    })

                @MainActor private var $count {
                    get {
                        _count.projectedValue
                    }
                }
            }
            """,
            macros: macros
        )
    }

    func testLet() {
        assertMacroExpansion(
            """
            struct V {
                @State let count = 0
            }
            """,
            expandedSource: """
            struct V {
                let count = 0
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@State can only be applied to a 'var' declaration", line: 2, column: 12)],
            macros: macros
        )
    }

    func testStatic() {
        assertMacroExpansion(
            """
            struct V {
                @State static var count = 0
            }
            """,
            expandedSource: """
            struct V {
                static var count = 0
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@State can't be applied to a static property; state belongs to a view", line: 2, column: 12)],
            macros: macros
        )
    }

    func testComputed() {
        assertMacroExpansion(
            """
            struct V {
                @State var count: Int { 0 }
            }
            """,
            expandedSource: """
            struct V {
                var count: Int { 0 }
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@State can't be applied to a computed property", line: 2, column: 27)],
            macros: macros
        )
    }

    func testNoTypeOrValue() {
        assertMacroExpansion(
            """
            struct V {
                @State var count
            }
            """,
            expandedSource: """
            struct V {
                var count
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@State needs a type annotation or an initial value", line: 2, column: 16)],
            macros: macros
        )
    }
}
