//
//  PreviewMacro.swift
//  NucleantUIMacros
//
//  The compiler plugin behind `@Preview`. See `Preview/Preview.swift` in
//  `NucleantUI` for the record it expands to and `PreviewRuntime` for what
//  reads it.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@Preview` — registers a file-scope function returning a view as a
/// preview, so a `NUCLEANT_PREVIEW` build shows it in place of the app.
///
/// * **peer**: one `_PreviewRecord` constant placed in the previews' linker
///   section, which `PreviewRuntime` walks at launch — Swift runs nothing
///   at load time, so a section is how a declaration in any file reaches
///   the runtime. Its value is a C function that writes the preview's
///   `_PreviewEntry` (name, file ID and path, line, the function) into memory the
///   runtime hands it: the constant itself has to be statically
///   initialisable, which a C function pointer is and a Swift closure or
///   `String` is not.
///
/// The record exists only in a build with `NUCLEANT_PREVIEW` defined; in
/// any other build the expansion is empty and the function is an ordinary
/// unused function. The section is named per object format: Mach-O wants
/// `segment,section`, ELF and wasm a plain name usable as a C identifier
/// (for the linker's `__start_`/`__stop_` symbols).
public struct PreviewMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: node, message: PreviewMacroMessage.notAFunction))
            return []
        }
        guard context.lexicalContext.isEmpty else {
            context.diagnose(Diagnostic(node: node, message: PreviewMacroMessage.notAtFileScope))
            return []
        }
        let signature = function.signature
        guard signature.parameterClause.parameters.isEmpty else {
            context.diagnose(Diagnostic(node: signature.parameterClause, message: PreviewMacroMessage.hasParameters))
            return []
        }
        guard signature.effectSpecifiers?.asyncSpecifier == nil,
              signature.effectSpecifiers?.throwsClause == nil else {
            context.diagnose(Diagnostic(node: signature, message: PreviewMacroMessage.asyncOrThrows))
            return []
        }
        guard signature.returnClause != nil, function.genericParameterClause == nil else {
            context.diagnose(Diagnostic(node: function.name, message: PreviewMacroMessage.noView))
            return []
        }

        // `@Preview("Title")` names the tab; plain `@Preview` uses the
        // function's name.
        let name: ExprSyntax
        if case .argumentList(let arguments) = node.arguments, let first = arguments.first {
            name = first.expression
        } else {
            name = ExprSyntax(StringLiteralExprSyntax(content: function.name.text))
        }
        let empty = ExprSyntax(StringLiteralExprSyntax(content: ""))
        let location = context.location(of: node, at: .afterLeadingTrivia, filePathMode: .fileID)
        let file = location?.file ?? empty
        let path = context.location(of: node, at: .afterLeadingTrivia, filePathMode: .filePath)?.file ?? empty
        let line = location?.line ?? ExprSyntax(IntegerLiteralExprSyntax(0))
        let record = context.makeUniqueName("preview")
        let value: ExprSyntax = """
            { NucleantUI._PreviewEntry._write(to: $0, name: \(name), fileID: \(file), filePath: \(path), line: \(line), content: \(function.name.trimmed)) }
            """

        return ["""
            #if NUCLEANT_PREVIEW
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            @section("__DATA,nucleant_prev") @used
            private let \(record): NucleantUI._PreviewRecord = \(value)
            #elseif os(Windows)
            @section("nucleant_previews$m") @used
            private let \(record): NucleantUI._PreviewRecord = \(value)
            #else
            @section("nucleant_previews") @used
            private let \(record): NucleantUI._PreviewRecord = \(value)
            #endif
            #endif
            """]
    }
}

enum PreviewMacroMessage: DiagnosticMessage {
    case notAFunction
    case notAtFileScope
    case hasParameters
    case asyncOrThrows
    case noView

    var message: String {
        switch self {
        case .notAFunction: return "@Preview can only be applied to a function"
        case .notAtFileScope: return "@Preview functions must be declared at file scope"
        case .hasParameters: return "a @Preview function takes no parameters"
        case .asyncOrThrows: return "a @Preview function cannot be async or throw"
        case .noView: return "a @Preview function returns its view: '-> some View'"
        }
    }

    var diagnosticID: MessageID {
        switch self {
        case .notAFunction: return MessageID(domain: "NucleantUIMacros", id: "previewNotAFunction")
        case .notAtFileScope: return MessageID(domain: "NucleantUIMacros", id: "previewNotAtFileScope")
        case .hasParameters: return MessageID(domain: "NucleantUIMacros", id: "previewHasParameters")
        case .asyncOrThrows: return MessageID(domain: "NucleantUIMacros", id: "previewAsyncOrThrows")
        case .noView: return MessageID(domain: "NucleantUIMacros", id: "previewNoView")
        }
    }

    var severity: DiagnosticSeverity { .error }
}
