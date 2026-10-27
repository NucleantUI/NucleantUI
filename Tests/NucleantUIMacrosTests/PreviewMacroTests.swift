//
//  PreviewMacroTests.swift
//  NucleantUIMacrosTests
//
//  What `@Preview` expands to — a record in the previews' section, only in
//  a NUCLEANT_PREVIEW build — and what it refuses.
//

import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import NucleantUIMacros

private let macros: [String: Macro.Type] = ["Preview": PreviewMacro.self]

final class PreviewMacroTests: XCTestCase {

    func testNamedPreview() {
        assertMacroExpansion(
            """
            @Preview("Ring")
            func ringPreview() -> some View {
                Ring()
            }
            """,
            expandedSource: """
            func ringPreview() -> some View {
                Ring()
            }

            #if NUCLEANT_PREVIEW
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            @section("__DATA,nucleant_prev") @used
            private let __macro_local_7previewfMu_: NucleantUI._PreviewRecord = {
                NucleantUI._PreviewEntry._write(to: $0, name: "Ring", fileID: "TestModule/test.swift", filePath: "test.swift", line: 1, content: ringPreview)
            }
            #elseif os(Windows)
            @section("nucleant_previews$m") @used
            private let __macro_local_7previewfMu_: NucleantUI._PreviewRecord = {
                NucleantUI._PreviewEntry._write(to: $0, name: "Ring", fileID: "TestModule/test.swift", filePath: "test.swift", line: 1, content: ringPreview)
            }
            #else
            @section("nucleant_previews") @used
            private let __macro_local_7previewfMu_: NucleantUI._PreviewRecord = {
                NucleantUI._PreviewEntry._write(to: $0, name: "Ring", fileID: "TestModule/test.swift", filePath: "test.swift", line: 1, content: ringPreview)
            }
            #endif
            #endif
            """,
            macros: macros
        )
    }

    func testUnnamedPreviewIsTitledByItsFunction() {
        assertMacroExpansion(
            """
            @Preview
            func ringPreview() -> some View {
                Ring()
            }
            """,
            expandedSource: """
            func ringPreview() -> some View {
                Ring()
            }

            #if NUCLEANT_PREVIEW
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            @section("__DATA,nucleant_prev") @used
            private let __macro_local_7previewfMu_: NucleantUI._PreviewRecord = {
                NucleantUI._PreviewEntry._write(to: $0, name: "ringPreview", fileID: "TestModule/test.swift", filePath: "test.swift", line: 1, content: ringPreview)
            }
            #elseif os(Windows)
            @section("nucleant_previews$m") @used
            private let __macro_local_7previewfMu_: NucleantUI._PreviewRecord = {
                NucleantUI._PreviewEntry._write(to: $0, name: "ringPreview", fileID: "TestModule/test.swift", filePath: "test.swift", line: 1, content: ringPreview)
            }
            #else
            @section("nucleant_previews") @used
            private let __macro_local_7previewfMu_: NucleantUI._PreviewRecord = {
                NucleantUI._PreviewEntry._write(to: $0, name: "ringPreview", fileID: "TestModule/test.swift", filePath: "test.swift", line: 1, content: ringPreview)
            }
            #endif
            #endif
            """,
            macros: macros
        )
    }

    func testRefusesAFunctionWithParameters() {
        assertMacroExpansion(
            """
            @Preview
            func ringPreview(progress: Double) -> some View {
                Ring(progress: progress)
            }
            """,
            expandedSource: """
            func ringPreview(progress: Double) -> some View {
                Ring(progress: progress)
            }
            """,
            diagnostics: [DiagnosticSpec(message: "a @Preview function takes no parameters", line: 2, column: 17)],
            macros: macros
        )
    }

    func testRefusesAMethod() {
        assertMacroExpansion(
            """
            struct Previews {
                @Preview
                func ringPreview() -> some View {
                    Ring()
                }
            }
            """,
            expandedSource: """
            struct Previews {
                func ringPreview() -> some View {
                    Ring()
                }
            }
            """,
            diagnostics: [DiagnosticSpec(message: "@Preview functions must be declared at file scope", line: 2, column: 5)],
            macros: macros
        )
    }

    func testRefusesAVariable() {
        assertMacroExpansion(
            """
            @Preview
            var ring: some View { Ring() }
            """,
            expandedSource: """
            var ring: some View { Ring() }
            """,
            diagnostics: [DiagnosticSpec(message: "@Preview can only be applied to a function", line: 1, column: 1)],
            macros: macros
        )
    }
}
