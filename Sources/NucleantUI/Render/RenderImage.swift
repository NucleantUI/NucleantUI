//
//  RenderImage.swift
//  NucleantUI
//
//  A view tree rendered to a bitmap, on the CPU — SwiftUI's `ImageRenderer`,
//  as a function.
//
//  No engine, no window, no GPU: the tree is laid out by `OffscreenRender`
//  and the display list is rasterized by a ThorVG software canvas straight
//  into a `RasterImage`'s own buffer. ThorVG's `ARGB8888` is exactly
//  `RasterImage`'s contract — premultiplied, row-major from the top-left — so
//  nothing is converted on the way out.
//
//  Being headless is the point: this path runs in a test target, on every
//  platform, before any window exists. `RenderTexture` is its GPU sibling,
//  for pixels a shader has to sample.
//

import NucleantThorVG

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
/// A `Shader`, `VertexShader`, `TextureView` or `ThorCanvas` inside draws
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

/// The display list → pixels step, on a ThorVG software canvas.
@MainActor
enum OffscreenRaster {

    /// `list` (in point coordinates, origin at the top-left) rasterized into
    /// an image `size × scale` pixels.
    static func image(of list: DisplayList, size: Size, scale: Double) -> RasterImage {
        let width = max(0, Int((size.width * scale).rounded()))
        let height = max(0, Int((size.height * scale).rounded()))
        guard width > 0, height > 0 else { return RasterImage(width: 0, height: 0, pixels: []) }

        // Before the canvas: `tvg_swcanvas_create` needs the engine up, and
        // `ThorDisplayRenderer`'s own call comes too late for it.
        ThorEngine.ensureInitialized()

        // ThorVG holds this pointer for as long as it is the canvas target,
        // so it is allocated rather than a local array's storage, and freed
        // only after the canvas is destroyed.
        let pixels = UnsafeMutableBufferPointer<UInt32>.allocate(capacity: width * height)
        defer { pixels.deallocate() }
        pixels.initialize(repeating: 0)

        guard let canvas = tvg_swcanvas_create(TVG_ENGINE_OPTION_DEFAULT) else {
            nucleantLogError("NucleantUI: renderImage — no ThorVG software canvas\n")
            return RasterImage(width: width, height: height, pixels: Array(pixels))
        }
        defer { _ = tvg_canvas_destroy(canvas) }

        let target = tvg_swcanvas_set_target(
            canvas,
            pixels.baseAddress,
            UInt32(width),          // stride, in pixels: tightly packed
            UInt32(width),
            UInt32(height),
            TVG_COLORSPACE_ARGB8888 // premultiplied ARGB — `RasterImage`'s own
        )
        guard target == TVG_RESULT_SUCCESS else {
            nucleantLogError("NucleantUI: renderImage — ThorVG target \(width)x\(height) refused (\(target))\n")
            return RasterImage(width: width, height: height, pixels: Array(pixels))
        }

        let renderer = ThorDisplayRenderer(canvas: canvas)
        renderer.scale = scale
        renderer.render(list)
        _ = tvg_canvas_draw(canvas, true)
        // Blocking by definition: the pixels are the return value, and
        // ThorVG may be writing them on its own threads until this returns.
        _ = tvg_canvas_sync(canvas)

        return RasterImage(width: width, height: height, pixels: Array(pixels))
    }
}
