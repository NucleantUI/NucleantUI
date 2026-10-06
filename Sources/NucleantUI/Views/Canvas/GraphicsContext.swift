//
//  GraphicsContext.swift
//  NucleantUI
//
//  What a `Canvas` renderer draws into: the node's own `SkCanvas`, with the
//  transform, opacity and clip a SwiftUI graphics context carries kept on
//  the context and applied around each draw.
//

#if SKIA_MODE

import NucleantSkia

/// What a ``Canvas`` renderer draws into.
///
/// It is a handle on the Skia canvas of the render node the canvas view sits
/// in — ``canvas`` — with SwiftUI's drawing calls on top: `fill`, `stroke`,
/// a transform, an opacity and clips. Points are in the canvas's own space:
/// the origin is its top-left, the units are points, and ``size`` is its
/// extent.
///
/// The state is a value. Copy the context, change the copy, and the original
/// keeps its own — that is what ``drawLayer(_:)`` does. Only the calls on the
/// context see that state; anything drawn on ``canvas`` directly does not
/// (see ``withCanvas(_:)``).
///
/// Gradients resolve against the whole canvas, not each path.
public struct GraphicsContext {
    /// The node's Skia canvas, positioned at this canvas's origin and cut to
    /// its frame. Drawing on it goes straight to the node, with none of this
    /// context's transform, opacity or clip applied.
    public let canvas: SkCanvas

    /// The canvas's extent.
    public let size: Size

    /// How opaque everything drawn from here on is.
    public var opacity: Double = 1

    /// Maps the points of what is drawn from here on. Change it with
    /// ``translateBy(x:y:)``, ``scaleBy(x:y:)``, ``rotate(by:)`` and
    /// ``concatenate(_:)``.
    public var transform: Transform = .identity

    /// The appearance dynamic colors resolve against.
    let colorScheme: ColorScheme

    /// Clips in effect, already mapped to the canvas's space, newest last.
    private var clips: [(path: Path, eoFill: Bool)] = []

    /// One of each, shared by every copy of the context — a draw never
    /// overlaps another.
    private let scratch = Scratch()

    private final class Scratch {
        let fill = SkPaint()
        let stroke = SkPaint()
        let image = SkPaint()
        let path = SkPath()
        init() {
            fill.setStyle(.fill)
            stroke.setStyle(.stroke)
        }
    }

    init(canvas: SkCanvas, size: Size, colorScheme: ColorScheme) {
        self.canvas = canvas
        self.size = size
        self.colorScheme = colorScheme
    }

    // MARK: Transform

    public mutating func translateBy(x: Double, y: Double) {
        concatenate(.translation(x: x, y: y))
    }

    public mutating func scaleBy(x: Double, y: Double) {
        concatenate(.scale(x: x, y: y))
    }

    public mutating func rotate(by angle: Angle) {
        concatenate(.rotation(angle))
    }

    /// `other` applied in the space the context draws in now, before the
    /// transform already in effect.
    public mutating func concatenate(_ other: Transform) {
        transform = transform.concatenating(other)
    }

    // MARK: Clip

    /// Everything drawn from here on is cut to `path`, narrowing any clip
    /// already in effect. The path is taken in the context's space as it is
    /// now: a later transform does not move it.
    public mutating func clip(to path: Path, eoFill: Bool = false) {
        clips.append((path.applying(transform), eoFill))
    }

    public mutating func clip(to rect: Rect) {
        clip(to: Path(rect))
    }

    // MARK: Drawing

    public func fill(_ path: Path, with style: ShapeStyle, eoFill: Bool = false) {
        draw(path, eoFill: eoFill) { canvas, skPath in
            apply(style, to: scratch.fill)
            canvas.drawPath(skPath, paint: scratch.fill)
            drawEmbedded(path, on: canvas)
        }
    }

    public func fill(_ path: Path, with color: Color, eoFill: Bool = false) {
        fill(path, with: .color(color), eoFill: eoFill)
    }

    public func stroke(_ path: Path, with style: ShapeStyle, style strokeStyle: StrokeStyle) {
        guard strokeStyle.lineWidth > 0 else { return }
        draw(path, eoFill: false) { canvas, skPath in
            let paint = scratch.stroke
            paint.setStrokeWidth(strokeStyle.lineWidth)
            paint.setStrokeCap(Self.cap(strokeStyle.lineCap))
            paint.setStrokeJoin(Self.join(strokeStyle.lineJoin))
            if strokeStyle.dash.isEmpty {
                paint.clearPathEffect()
            } else {
                // Skia wants on/off pairs; an odd pattern repeats to make them.
                var intervals = strokeStyle.dash.map { Float($0) }
                if intervals.count % 2 == 1 { intervals += intervals }
                if let dash = SkDashPathEffect.make(intervals: intervals, phase: Float(strokeStyle.dashPhase)) {
                    paint.setPathEffect(dash)
                } else {
                    paint.clearPathEffect()
                }
            }
            apply(style, to: paint)
            canvas.drawPath(skPath, paint: paint)
        }
    }

    public func stroke(_ path: Path, with style: ShapeStyle, lineWidth: Double = 1) {
        stroke(path, with: style, style: StrokeStyle(lineWidth: lineWidth))
    }

    public func stroke(_ path: Path, with color: Color, style: StrokeStyle) {
        stroke(path, with: .color(color), style: style)
    }

    public func stroke(_ path: Path, with color: Color, lineWidth: Double = 1) {
        stroke(path, with: .color(color), style: StrokeStyle(lineWidth: lineWidth))
    }

    /// Run `content` against a copy of this context: what it changes
    /// (transform, opacity, clip) ends with it.
    public func drawLayer(_ content: (inout GraphicsContext) -> Void) {
        var layer = self
        content(&layer)
    }

    /// Run `body` on ``canvas`` with this context's clip, transform and
    /// opacity applied — Skia calls inside it land where the context's own
    /// would. Whatever `body` changes on the canvas is undone after.
    public func withCanvas(_ body: (SkCanvas) -> Void) {
        let saved = canvas.save()
        applyState()
        if opacity < 1 {
            canvas.saveLayerAlphaf(Float(max(opacity, 0)))
        }
        body(canvas)
        canvas.restoreToCount(saved)
    }

    // MARK: Skia

    /// The clips, then the transform, on the canvas — inside a `save`.
    private func applyState() {
        for clip in clips {
            scratch.path.reset()
            Self.append(clip.path, to: scratch.path)
            scratch.path.setFillType(clip.eoFill ? .evenOdd : .winding)
            canvas.clipPath(scratch.path, doAntiAlias: true)
        }
        if !transform.isIdentity {
            canvas.concat(SkMatrix(
                scaleX: Float(transform.e11), skewX: Float(transform.e12), transX: Float(transform.e13),
                skewY: Float(transform.e21), scaleY: Float(transform.e22), transY: Float(transform.e23)
            ))
        }
    }

    private func draw(_ path: Path, eoFill: Bool, _ body: (SkCanvas, SkPath) -> Void) {
        guard !path.isEmpty, opacity > 0 else { return }
        let saved = canvas.save()
        applyState()
        // The clips above used the scratch path; the shape comes after.
        scratch.path.reset()
        Self.append(path, to: scratch.path)
        scratch.path.setFillType(eoFill ? .evenOdd : .winding)
        body(canvas, scratch.path)
        canvas.restoreToCount(saved)
    }

    // MARK: Text and images

    /// The text and images in `path`, painted with the fill already set on
    /// the fill paint. Drawing happens on the main actor, which owns the
    /// fonts and the measurer.
    private func drawEmbedded(_ path: Path, on canvas: SkCanvas) {
        guard path.elements.contains(where: {
            switch $0 {
            case .text, .image: return true
            default: return false
            }
        }) else { return }
        EmbeddedDrawing.draw(path, on: canvas, fill: scratch.fill, image: scratch.image, opacity: opacity)
    }

    private func apply(_ style: ShapeStyle, to paint: SkPaint) {
        let bounds = Rect(origin: .zero, size: size)
        switch style {
        case .color(let color):
            paint.clearShader()
            paint.setColor(rgba(color))
        case .linearGradient(let gradient, let startPoint, let endPoint):
            let start = startPoint.resolved(in: bounds)
            let end = endPoint.resolved(in: bounds)
            let (colors, positions) = stops(gradient)
            paint.setColor(SIMD4<UInt8>(0, 0, 0, alpha))
            if let shader = SkGradientShader.makeLinear(
                from: SIMD2<Float>(start), to: SIMD2<Float>(end),
                colors: colors, positions: positions
            ) {
                paint.setShader(shader)
            } else {
                paint.clearShader()
            }
        case .radialGradient(let gradient, let center, let startRadius, let endRadius):
            let point = SIMD2<Float>(center.resolved(in: bounds))
            let (colors, positions) = stops(gradient)
            paint.setColor(SIMD4<UInt8>(0, 0, 0, alpha))
            if let shader = SkGradientShader.makeTwoPointConical(
                start: point, startRadius: Float(startRadius),
                end: point, endRadius: Float(endRadius),
                colors: colors, positions: positions
            ) {
                paint.setShader(shader)
            } else {
                paint.clearShader()
            }
        }
    }

    /// The opacity as the paint's alpha, which a shader's colors are
    /// multiplied by.
    private var alpha: UInt8 { UInt8((min(max(opacity, 0), 1) * 255).rounded()) }

    private func rgba(_ color: Color) -> SIMD4<UInt8> {
        let (r, g, b, a) = color.resolved(for: colorScheme).rgba8
        return SIMD4(r, g, b, UInt8((Double(a) * min(max(opacity, 0), 1)).rounded()))
    }

    private func stops(_ gradient: Gradient) -> (colors: [SIMD4<Float>], positions: [Float]) {
        var colors: [SIMD4<Float>] = []
        var positions: [Float] = []
        for stop in gradient.stops {
            let (r, g, b, a) = stop.color.resolved(for: colorScheme).rgba8
            colors.append(SIMD4<Float>(Float(r), Float(g), Float(b), Float(a)) / 255)
            positions.append(Float(stop.location))
        }
        return (colors, positions)
    }

    private static func append(_ path: Path, to skPath: SkPath) {
        for element in path.elements {
            switch element {
            case .move(let point):
                skPath.moveTo(point)
            case .line(let point):
                skPath.lineTo(point)
            case .quad(let control, let end):
                skPath.quadTo(control, end)
            case .cubic(let c1, let c2, let end):
                skPath.cubicTo(c1, c2, end)
            case .close:
                skPath.close()
            case .rect(let rect, let radiusX, let radiusY):
                if radiusX > 0 || radiusY > 0 {
                    skPath.addRRect(pos: rect.origin, size: rect.size, radius: SIMD2(radiusX, radiusY))
                } else {
                    skPath.addRect(pos: rect.origin, size: rect.size)
                }
            case .ellipse(let center, let radiusX, let radiusY):
                let radius = SIMD2(radiusX, radiusY)
                skPath.addOval(pos: center - radius, size: radius * 2)
            case .text, .image:
                // Not geometry: drawn after the path, by `drawEmbedded`.
                break
            }
        }
    }

    private static func cap(_ cap: LineCap) -> SkStrokeCap {
        switch cap {
        case .butt:   return .butt
        case .round:  return .round
        case .square: return .square
        }
    }

    private static func join(_ join: LineJoin) -> SkStrokeJoin {
        switch join {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}

/// The text and images in a path, drawn with Skia. Its own fonts and images
/// caches, apart from the display-list renderer's. Everything here runs
/// while a node is drawn, on the main actor, which the font registry and the
/// measurer belong to.
private enum EmbeddedDrawing {
    /// Text in the fill paint's color or shader, an image faded by `opacity`.
    static func draw(_ path: Path, on canvas: SkCanvas, fill: SkPaint, image paint: SkPaint, opacity: Double) {
        for element in path.elements {
            switch element {
            case .text(let string, let origin, let font):
                drawText(string, at: origin, font: font, on: canvas, paint: fill)
            case .image(let raster, let rect):
                guard rect.width > 0, rect.height > 0, let image = skImage(for: raster) else { continue }
                paint.setAlphaf(Float(min(max(opacity, 0), 1)))
                canvas.drawImageRect(image, pos: SIMD2<Float>(rect.origin), size: SIMD2<Float>(rect.size), paint: paint)
            default:
                break
            }
        }
    }

    private static func drawText(_ string: String, at origin: Point, font: Font, on canvas: SkCanvas, paint: SkPaint) {
        guard !string.isEmpty else { return }
        let skFont = skFont(for: font)
        // The first baseline an ascent below the box's top, the rest a line
        // height apart.
        let metrics = MainActor.assumeIsolated { TextMeasurer.lineMetrics(for: font) }
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() where !line.isEmpty {
            canvas.drawString(
                String(line),
                x: Float(origin.x),
                y: Float(origin.y + metrics.ascent + Double(index) * metrics.lineHeight),
                font: skFont,
                paint: paint
            )
        }
    }

    /// ThorVG sizes text in points at 96 DPI and draws it at `size × 96/72`
    /// units; layout measures with ThorVG, so Skia is given the same factor
    /// and the glyphs fill the box that was made for them.
    private static let pointScale = 96.0 / 72.0

    nonisolated(unsafe) private static var typefaces: [String: SkTypeface] = [:]
    nonisolated(unsafe) private static var defaultTypeface: SkTypeface?

    private struct FontKey: Hashable {
        let family: String?
        let size: Double
        let slanted: Bool
    }
    nonisolated(unsafe) private static var fonts: [FontKey: SkFont] = [:]

    private static func skFont(for font: Font) -> SkFont {
        let family = MainActor.assumeIsolated { FontRegistry.resolve(font) }
        // No italic face found: a synthetic shear still reads as italic.
        let slanted = font.isItalic && !(family?.contains("Italic") ?? false)
        let key = FontKey(family: family, size: font.size, slanted: slanted)
        if let cached = fonts[key] { return cached }
        let made = SkFont(typeface(for: family), size: Float(font.size * pointScale))
        made.setSubpixel(true)
        made.setEdging(.antiAlias)
        if slanted { made.setSkewX(-0.2) }
        fonts[key] = made
        return made
    }

    private static func typeface(for family: String?) -> SkTypeface? {
        if let family {
            if let loaded = typefaces[family] { return loaded }
            if let path = MainActor.assumeIsolated({ FontRegistry.path(ofResolved: family) }), let made = SkFontMgr.makeFromFile(path) {
                typefaces[family] = made
                return made
            }
        }
        if defaultTypeface == nil {
            defaultTypeface = SkFontMgr.matchFamilyStyle(nil)
        }
        return defaultTypeface
    }

    /// Skia images by the `RasterImage` they were made from, which is held
    /// with its image so its identifier stays its own. Emptied when it gets
    /// large; an image still in use is simply made again.
    nonisolated(unsafe) private static var images: [ObjectIdentifier: (source: RasterImage, image: SkImage)] = [:]

    /// `RasterImage`'s pixels are premultiplied ARGB words — BGRA bytes on a
    /// little-endian machine, which is Skia's `bgra8888`.
    private static func skImage(for raster: RasterImage) -> SkImage? {
        let key = ObjectIdentifier(raster)
        if let cached = images[key] { return cached.image }
        guard let made = SkImages.rasterFromPixmapCopy(
            raster.pixels,
            size: SIMD2(Int32(raster.width), Int32(raster.height))
        ) else { return nil }
        if images.count >= 64 { images.removeAll(keepingCapacity: true) }
        images[key] = (raster, made)
        return made
    }
}

#endif
