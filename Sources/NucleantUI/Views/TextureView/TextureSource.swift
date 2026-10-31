//
//  TextureSource.swift
//  NucleantUI
//
//  The producer side of a `TextureView`: an object that fills the view's GPU
//  texture from outside the view tree, whenever it has a frame — a browser's
//  compositor, a video decoder, a camera.
//

import NucleantVulkan

/// Fills a `TextureView`'s texture, and hears about the view it fills.
///
/// ```swift
/// @MainActor @Observable
/// final class Player: TextureSource {
///     private var texture: ViewTexture?
///
///     func textureDidChange(_ texture: ViewTexture) {
///         self.texture = texture            // render at texture.pixelWidth × pixelHeight
///     }
///     func textureDidDisappear(_ texture: ViewTexture) {
///         self.texture = nil
///     }
///     func decoder(didDecode surface: IOSurfaceRef) {
///         texture?.write(ioSurface: Unmanaged.passUnretained(surface).toOpaque())
///     }
/// }
/// ```
///
/// A class, compared by identity: the same object is the same source, and a
/// `TextureView` handed a different one tells the old one it lost the view
/// and the new one it has it. Every callback runs on the main actor, after
/// the layout pass that caused it — never during one.
@MainActor
public protocol TextureSource: AnyObject {
    
    associatedtype Node: NucleantContainerNode
    /// The view has a texture, or its texture changed size or scale — the
    /// first call is the view appearing. Frames written from now on should
    /// be `texture.pixelWidth × texture.pixelHeight`.
    func textureDidChange(_ texture: ViewTexture<Node>)

    /// The view left the tree, or was handed another source. `texture`
    /// accepts no more writes.
    func textureDidDisappear(_ texture: ViewTexture<Node>)

    /// The view moved in its window, or what clips it changed, while its
    /// size and scale stayed the same — `texture.frame` and
    /// `texture.visibleFrame` say where it is now. (A move together with a
    /// resize is a `textureDidChange`.) Ignored by default: a source that
    /// only fills the texture has no use for where it is shown.
    func textureDidMove(_ texture: ViewTexture<Node>)

    /// Input over the view — see `TextureInputEvent`. Ignored by default.
    func textureInput(_ event: TextureInputEvent)
}

extension TextureSource {
    public func textureDidMove(_ texture: ViewTexture<Node>) {}
    public func textureInput(_ event: TextureInputEvent) {}
}

/// Input a `TextureView` passes to its source, in the view's own space
/// (points, origin top-left).
///
/// Pointer events follow a mouse over the view; a press that starts on it
/// keeps reporting `pointerDragged` to it after leaving it, until
/// `pointerUp`. Keys go to the view that was last pressed — pressing
/// anywhere else takes them away, with `focusChanged(false)`.
public enum TextureInputEvent: Sendable {
    case pointerMoved(Point)
    case pointerExited
    case pointerDown(Point)
    case pointerDragged(Point)
    /// `inside` is false when the press was released off the view.
    case pointerUp(Point, inside: Bool)
    /// A wheel or trackpad delta, in points, at the last pointer position
    /// this view was told of.
    case scroll(dx: Double, dy: Double)
    /// `keyCode` is the platform's virtual key code (`NSEvent.keyCode`).
    case keyDown(keyCode: UInt16, characters: String?, modifiers: EventModifiers)
    case keyUp(keyCode: UInt16, characters: String?, modifiers: EventModifiers)
    case focusChanged(Bool)
    /// An Edit menu command (⌘C, ⌘V, …) while the view has the keys — on
    /// macOS these never arrive as key presses.
    case edit(EditCommand)
}

/// A `TextureView`'s texture, as its source sees it: the size to render at,
/// and the way in for frames.
///
/// Every write is a copy into an image the view owns, finished before the
/// call returns — so what was written may be reused or recycled by the
/// producer at once, and the view shows whole frames only.
@MainActor
public final class ViewTexture<Node: NucleantContainerNode> {
    /// The view's frame, in points.
    public internal(set) var size: Size
    /// Backing-store pixels per point.
    public internal(set) var scale: Double

    /// Where the view is in its window: points from the window's top-left.
    public internal(set) var origin: Point

    /// The view's frame in its window, in points.
    public var frame: Rect { Rect(origin: origin, size: size) }

    /// The part of `frame` that shows — `frame` cut to whatever clips the
    /// view (a scroll view, `.clipped()`), in the same space. Zero-sized
    /// when none of it does.
    public internal(set) var visibleFrame: Rect

    /// The window the view is in — `nil` for a tree laid out without one.
    weak var window: HostingWindow<Node>?

    /// The size to render frames at: the frame in pixels, rounded up.
    public var pixelWidth: Int { max(1, Int((size.width * scale).rounded(.up))) }
    public var pixelHeight: Int { max(1, Int((size.height * scale).rounded(.up))) }

    /// False once the view has let the texture go; writes are then refused.
    public internal(set) var isAttached = true

    let node: ExternalTextureNode<Node>
    let container: Node
    private unowned let engine: VulkanRenderEngine<Node>

    init(
        node: ExternalTextureNode<Node>,
        container: Node,
        engine: VulkanRenderEngine<Node>,
        frame: Rect,
        visibleFrame: Rect,
        scale: Double
    ) {
        self.node = node
        self.container = container
        self.engine = engine
        self.size = frame.size
        self.origin = frame.origin
        self.visibleFrame = visibleFrame
        self.scale = scale
    }

    #if os(macOS) || os(iOS)
    /// Copy an `IOSurfaceRef` (BGRA8) into the texture at pixel (`x`, `y`),
    /// on the GPU. The surface is not touched after this returns. Cut to the
    /// texture's size when bigger; a smaller one leaves the rest as it was.
    @discardableResult
    public func write(ioSurface: UnsafeMutableRawPointer, x: Int = 0, y: Int = 0) -> Bool {
        guard isAttached else { return false }
        let written = engine.renderDevice.writeExternalTexture(node, ioSurface: ioSurface, x: x, y: y)
        if written { container.needsRender = true }
        return written
    }
    #endif

    /// Copy BGRA8 pixels — `height` rows, `bytesPerRow` apart — into the
    /// texture at pixel (`x`, `y`). The CPU fallback: a producer with a GPU
    /// surface to hand over should use `write(ioSurface:)`.
    @discardableResult
    public func write(
        bgra pixels: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        x: Int = 0,
        y: Int = 0
    ) -> Bool {
        guard isAttached else { return false }
        let written = engine.renderDevice.writeExternalTexture(
            node, bgra: pixels, width: width, height: height, bytesPerRow: bytesPerRow, x: x, y: y
        )
        if written { container.needsRender = true }
        return written
    }

    /// What the texture holds, as tightly packed BGRA8 rows top row first,
    /// at the image's own size — which may be bigger than `pixelWidth ×
    /// pixelHeight` (images are allocated in granules). `nil` before the
    /// first write. Blocks on the GPU: for tests and debugging only.
    public func readPixels() -> (width: Int, height: Int, bgra: [UInt8])? {
        guard isAttached, let bytes = engine.renderDevice.readExternalTexture(node) else { return nil }
        return (Int(node.width), Int(node.height), bytes)
    }
}
