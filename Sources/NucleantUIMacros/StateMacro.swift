//
//  StateMacro.swift
//  NucleantUIMacros
//
//  The compiler plugin behind `@State`. See `State/State.swift` in
//  `NucleantUI` for the storage it expands to.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// `@State` — a property whose value lives in the state store, with its
/// initial value made once, when that state is created.
///
/// * **peer**: `_name`, the `_StateProperty` storage — given the initial
///   value as a closure, so constructing the view never evaluates it — and
///   `$name`, the binding, as visible as the property.
/// * **accessor**: `get`/`nonmutating set` through `_name`, with the
///   property's own `willSet`/`didSet` run inside the setter; and, when
///   there is no initial value, an `init` accessor so an initializer can
///   assign the property.
///
/// A property with an optional type and no initializer starts at `nil`, as
/// it did as a property wrapper.
public struct StateMacro: AccessorMacro, PeerMacro {

    // MARK: Peers

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let property = StateProperty(declaration, attribute: node, in: context, diagnose: true) else { return [] }
        let name = property.name
        let access = property.access

        var peers: [DeclSyntax] = []
        if let initial = property.initialValue {
            let storage = property.type.map { "_StateProperty<\($0)>" } ?? "_StateProperty"
            peers.append("private var _\(raw: name) = \(raw: storage)({ \(raw: initial) })")
            if let type = property.type {
                peers.append(projection(access: access, name: name, type: type))
            } else {
                // No type to spell `Binding<…>` with: the initializer gives it
                // one, and `@_StateProjectedValue` replaces it with a getter,
                // so it is only ever type-checked.
                peers.append("""
                    @MainActor @_StateProjectedValue \(raw: access)var $\(raw: name) = _StateProperty({ \(raw: initial) }).projectedValue
                    """)
            }
        } else if let type = property.type {
            peers.append("private var _\(raw: name): _StateProperty<\(raw: type)>")
            peers.append(projection(access: access, name: name, type: type))
        }
        return peers
    }

    private static func projection(access: String, name: String, type: String) -> DeclSyntax {
        """
        @MainActor \(raw: access)var $\(raw: name): Binding<\(raw: type)> {
            _\(raw: name).projectedValue
        }
        """
    }

    // MARK: Accessors

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        // Diagnosed by the peer role; reported once is enough.
        guard let property = StateProperty(declaration, attribute: node, in: context, diagnose: false) else { return [] }
        let storage = "_\(property.name)"

        var accessors: [AccessorDeclSyntax] = []
        if property.initialValue == nil {
            accessors.append("""
                @storageRestrictions(initializes: \(raw: storage))
                init(initialValue) {
                    \(raw: storage) = _StateProperty(initialValue: initialValue)
                }
                """)
        }
        accessors.append("""
            get {
                \(raw: storage).wrappedValue
            }
            """)
        accessors.append(setter(storage: storage, property: property, in: context))
        return accessors
    }

    /// `nonmutating set`, with the observers the property was declared with
    /// run around the write, as the compiler runs them for a stored property:
    /// `willSet` with the new value before it, `didSet` with the old one after.
    private static func setter(
        storage: String,
        property: StateProperty,
        in context: some MacroExpansionContext
    ) -> AccessorDeclSyntax {
        var lines: [String] = []
        let oldValue = context.makeUniqueName("oldValue").text
        if property.didSet != nil {
            lines.append("let \(oldValue) = \(storage).wrappedValue")
        }
        if let willSet = property.willSet {
            let parameter = willSet.parameters?.name.text ?? "newValue"
            lines.append("({ \(parameter) in\n\(willSet.body?.statements.trimmedDescription ?? "")\n})(newValue)")
        }
        lines.append("\(storage).wrappedValue = newValue")
        if let didSet = property.didSet {
            let parameter = didSet.parameters?.name.text ?? "oldValue"
            lines.append("({ \(parameter) in\n\(didSet.body?.statements.trimmedDescription ?? "")\n})(\(oldValue))")
        }
        return """
            nonmutating set {
                \(raw: lines.joined(separator: "\n"))
            }
            """
    }
}

/// `@_StateProjectedValue` on `$name` — a getter reading `_name`'s
/// projection, in place of the initializer that only gave `$name` a type.
public struct StateProjectedValueMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              let name = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              name.hasPrefix("$")
        else { return [] }
        return ["""
            get {
                _\(raw: name.dropFirst()).projectedValue
            }
            """]
    }
}

/// What `@State` needs from the property it is attached to.
private struct StateProperty {
    let name: String
    /// The declared type, if written.
    let type: String?
    /// The initializer's expression — or `nil` for an optional with none.
    /// Absent when the caller has to supply the value.
    let initialValue: String?
    /// The property's access, for `$name`: `public `, `private `, … or
    /// nothing for internal. A setter-only restriction (`private(set)`)
    /// doesn't apply to a getter-only projection.
    let access: String
    let willSet: AccessorDeclSyntax?
    let didSet: AccessorDeclSyntax?

    /// Reads the declaration, diagnosing what `@State` can't be applied to
    /// when `diagnose` is set.
    init?(
        _ declaration: some DeclSyntaxProtocol,
        attribute: AttributeSyntax,
        in context: some MacroExpansionContext,
        diagnose: Bool
    ) {
        func fail(_ message: StateMacroMessage, at node: some SyntaxProtocol) {
            if diagnose {
                context.diagnose(Diagnostic(node: node, message: message))
            }
        }
        guard let variable = declaration.as(VariableDeclSyntax.self) else {
            fail(.notAVariable, at: attribute)
            return nil
        }
        guard variable.bindingSpecifier.tokenKind == .keyword(.var) else {
            fail(.notAVar, at: variable.bindingSpecifier)
            return nil
        }
        if let modifier = variable.modifiers.first(where: { ["static", "class"].contains($0.name.text) }) {
            fail(.staticProperty, at: modifier)
            return nil
        }
        guard variable.bindings.count == 1, let binding = variable.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
        else {
            fail(.multipleBindings, at: variable.bindings)
            return nil
        }

        var willSet: AccessorDeclSyntax?
        var didSet: AccessorDeclSyntax?
        if let accessors = binding.accessorBlock {
            guard case .accessors(let list) = accessors.accessors else {
                fail(.computedProperty, at: accessors)
                return nil
            }
            for accessor in list {
                switch accessor.accessorSpecifier.text {
                case "willSet": willSet = accessor
                case "didSet": didSet = accessor
                default:
                    fail(.computedProperty, at: accessor)
                    return nil
                }
            }
        }

        let type = binding.typeAnnotation?.type
        let isOptional = type.map { type in
            type.is(OptionalTypeSyntax.self)
                || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
                || type.as(IdentifierTypeSyntax.self)?.name.text == "Optional"
        } ?? false
        let initialValue = binding.initializer?.value.trimmedDescription ?? (isOptional ? "nil" : nil)
        if type == nil && initialValue == nil {
            fail(.noTypeOrValue, at: pattern)
            return nil
        }

        var access = ""
        for modifier in variable.modifiers where modifier.detail == nil {
            switch modifier.name.text {
            case "private", "fileprivate", "internal", "package", "public":
                access = "\(modifier.name.text) "
            case "open":
                access = "public "
            default:
                continue
            }
        }

        self.name = pattern.identifier.text
        self.type = type?.trimmedDescription
        self.initialValue = initialValue
        self.access = access
        self.willSet = willSet
        self.didSet = didSet
    }
}

enum StateMacroMessage: String, DiagnosticMessage {
    case notAVariable
    case notAVar
    case staticProperty
    case multipleBindings
    case computedProperty
    case noTypeOrValue

    var message: String {
        switch self {
        case .notAVariable: return "@State can only be applied to a property"
        case .notAVar: return "@State can only be applied to a 'var' declaration"
        case .staticProperty: return "@State can't be applied to a static property; state belongs to a view"
        case .multipleBindings: return "@State can only be applied to a single property per declaration"
        case .computedProperty: return "@State can't be applied to a computed property"
        case .noTypeOrValue: return "@State needs a type annotation or an initial value"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "NucleantUIMacros", id: "State.\(rawValue)")
    }

    var severity: DiagnosticSeverity { .error }
}
