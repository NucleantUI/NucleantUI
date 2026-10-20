//
//  Color+ShaderValue.swift
//  NucleantUI
//

/// A `vec4` of red, green, blue and alpha, as the color is drawn under the
/// color scheme of the view it is packed for — so a dynamic color reaches
/// the shader in the appearance the view shows.
extension Color: ShaderValue {
    public func pack(into bytes: inout [UInt8]) {
        let color = resolved(for: Color.packingScheme)
        Float4(Float(color.red), Float(color.green), Float(color.blue), Float(color.alpha)).pack(into: &bytes)
    }

    /// The scheme an input is being packed for: the view's, set by its slot
    /// around each pack. Light outside one — `render(into:)` has no view.
    /// Packing happens on the main thread only.
    nonisolated(unsafe) static var packingScheme: ColorScheme = .light
}
