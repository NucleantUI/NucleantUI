//
//  RenderImage.swift
//  NucleantUI
//
//  A view tree rendered to a bitmap, on the CPU — SwiftUI's `ImageRenderer`,
//  as a function.
//
//  No window and no engine: the tree is laid out by `OffscreenRender`, and
//  the display list is drawn on the GPU by Skia, through the same
//  `SkiaDisplayRenderer` the window uses, on a windowless Vulkan device of
//  its own (`OffscreenGPU`), then read back.
//
//  Needing no window is the point: this runs in a test target and before
//  any window exists. `RenderTexture` is its sibling for pixels that stay
//  on the GPU, for a shader to sample.
//

/// `content` laid out at `size` points and rasterized at `scale` pixels per
/// point.
///
/// ```swift
/// let badge = renderImage(size: Size(width: 64, height: 64), scale: 2) {
///     Badge(level: level)
/// }
/// Image(badge)          // 128×128 pixels, drawn at 64×64 points
/// ```
///
/// The tree is laid out exactly as it would be on screen at that size, and
/// then it is over: the view is a snapshot. It has no input, no hit testing
/// and no lifecycle — `onAppear` does not run — and it does not re-render for
/// its own state. Call this again for a new image.
///
/// A `Shader`, `TextureView` or `ThorCanvas` inside draws
/// nothing: their pixels come from the GPU, and there is none here. A
/// `.drawingGroup()` or `.shader(_:)` inside draws its content inline — the
/// node and the effect are flattened away, not applied.
///
/// A non-positive size gives an empty image.
@MainActor
public func renderImage<Content: View>(
    size: Size,
    scale: Double = 1,
    @ViewBuilder content: () -> Content
) -> RasterImage {
    renderImage(size: size, scale: scale, content: content())
}

/// `renderImage(size:scale:content:)` with the view as a value.
@MainActor
public func renderImage<Content: View>(
    size: Size,
    scale: Double = 1,
    content: Content
) -> RasterImage {
    var environment = EnvironmentValues()
    environment.displayScale = scale
    let tree = OffscreenRender(environment: environment)
    return OffscreenRaster.image(
        of: tree.list(of: content, size: size),
        size: size,
        scale: scale
    )
}

extension View {

    /// This view, laid out at `size` and rasterized — see
    /// `renderImage(size:scale:content:)`, which this is the trailing form of.
    ///
    /// Not a `ViewModifier`: it returns an image, not a view, the way
    /// SwiftUI's `ImageRenderer` is an object of its own rather than something
    /// applied to a view. `panel.image(size:)` reads like a modifier and is
    /// not one — nothing in a view tree changes by calling it.
    @MainActor
    public func image(size: Size, scale: Double = 1) -> RasterImage {
        renderImage(size: size, scale: scale, content: self)
    }
}

/// The display list → pixels step, on the GPU.
@MainActor
enum OffscreenRaster {

    /// `list` (in point coordinates, origin at the top-left) drawn into an
    /// image `size × scale` pixels. Transparent when there is no GPU to draw
    /// on, which `OffscreenGPU` reports.
    static func image(of list: DisplayList, size: Size, scale: Double) -> RasterImage {
        let width = max(0, Int((size.width * scale).rounded()))
        let height = max(0, Int((size.height * scale).rounded()))
        guard width > 0, height > 0 else { return RasterImage(width: 0, height: 0, pixels: []) }
        return OffscreenGPU.shared.image(of: list, width: width, height: height, scale: scale)
            ?? RasterImage(width: width, height: height, pixels: Array(repeating: 0, count: width * height))
    }
}
