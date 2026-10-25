//
//  Color.swift
//  NucleantUI
//

/// Light or dark appearance — `@Environment(\.colorScheme)`.
///
/// The window seeds it from the system appearance and follows it as it
/// changes; `.colorScheme(_:)` fixes it for a subtree. Dynamic styles
/// (`ShapeStyle.dynamic(light:dark:)`, and the semantic ones — `.primary`,
/// `.background`, …) resolve against whichever scheme is in effect where
/// they are drawn.
public enum ColorScheme: Hashable, Sendable {
    case light
    case dark
}

/// An sRGB color with straight (non-premultiplied) alpha, stored as 0…1
/// components. ThorVG takes 8-bit channels, so the renderer scales on the way
/// out — see `Color.rgba8`.
///
/// A `SIMD` vector of four `Float` lanes — red, green, blue, alpha, the
/// order a shader's `vec4` reads them — and nothing else: 16 bytes, so a
/// color's memory is the bytes a shader reads, and color math is vector
/// math.
public struct Color: Hashable, Sendable, SIMD {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, opacity: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = opacity
    }

    /// White-point grey.
    public init(white: Float, opacity: Float = 1) {
        self.init(red: white, green: white, blue: white, opacity: opacity)
    }

    /// `0xRRGGBB`, with alpha given separately — the form hex literals in
    /// designs come in.
    public init(hex: UInt32, opacity: Float = 1) {
        self.init(
            red:   Float((hex >> 16) & 0xFF) / 255,
            green: Float((hex >>  8) & 0xFF) / 255,
            blue:  Float( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// `Double`, as SwiftUI's: with a `Float` here, `color.opacity(0.5)`
    /// resolves to `View.opacity(_:)` and gives a faded view, not a color.
    public func opacity(_ value: Double) -> Color {
        var copy = self
        copy.alpha = alpha * Float(value)
        return copy
    }

    /// 8-bit channels in the order ThorVG's `set_fill_color(r:g:b:a:)` wants.
    public var rgba8: (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        func channel(_ value: Float) -> UInt8 {
            UInt8(Swift.max(0, Swift.min(1, value)) * 255)
        }
        return (channel(red), channel(green), channel(blue), channel(alpha))
    }

    public var isClear: Bool { alpha <= 0 }

    // MARK: SIMD

    public subscript(index: Int) -> Float {
        get {
            switch index {
            case 0: red
            case 1: green
            case 2: blue
            case 3: alpha
            default: preconditionFailure("Color has four lanes; \(index) is out of range")
            }
        }
        set {
            switch index {
            case 0: red = newValue
            case 1: green = newValue
            case 2: blue = newValue
            case 3: alpha = newValue
            default: preconditionFailure("Color has four lanes; \(index) is out of range")
            }
        }
    }

    /// Every lane zero — clear.
    public init() {
        self.init(red: 0, green: 0, blue: 0, opacity: 0)
    }

    public typealias MaskStorage = SIMD4<Int32>

    public typealias ArrayLiteralElement = Float

    public typealias Scalar = Float

    public var scalarCount: Int { 4 }

    /// `[red, green, blue, alpha]`.
    public init(arrayLiteral elements: Float...) {
        precondition(elements.count == 4, "a Color literal is [red, green, blue, alpha], not \(elements.count) values")
        self.init(red: elements[0], green: elements[1], blue: elements[2], opacity: elements[3])
    }
}

extension Color {
    public static let clear   = Color(red: 0, green: 0, blue: 0, opacity: 0)
    public static let black   = Color(white: 0)
    public static let white   = Color(white: 1)
    public static let gray    = Color(white: 0.5)
    public static let red     = Color(hex: 0xFF3B30)
    public static let orange  = Color(hex: 0xFF9500)
    public static let yellow  = Color(hex: 0xFFCC00)
    public static let green   = Color(hex: 0x34C759)
    public static let mint    = Color(hex: 0x00C7BE)
    public static let teal    = Color(hex: 0x30B0C7)
    public static let cyan    = Color(hex: 0x32ADE6)
    public static let blue    = Color(hex: 0x007AFF)
    public static let indigo  = Color(hex: 0x5856D6)
    public static let purple  = Color(hex: 0xAF52DE)
    public static let pink    = Color(hex: 0xFF2D55)
    public static let brown   = Color(hex: 0xA2845E)
}
