//
//  SkiaDisplayRenderer.swift
//  NucleantUI
//
//  Turns a `DisplayList` into Skia draw calls on a node's `SkCanvas`. It
//  draws the views in every build — the window canvas, `.drawingGroup()`,
//  the per-view painter, the `.shader` layers and all text. Skia is always
//  the renderer; see "Renderer" in Package.swift.
//
//  Skia is immediate: a draw call records into the surface, and nothing is
//  held between passes the way ThorVG's paints are. A render therefore
//  clears the canvas and draws the list again; the node's update flushes
//  the recording on the engine's queue.
//
//  The canvas is scaled once per render — layout runs in points, the canvas
//  is in backing-store pixels — and every command is drawn in points under
//  that. Stroke widths, dashes and glyphs scale with it. A command's clip is
//  set before its transform, as ThorVG applies a paint's transform to the
//  paint and not to its clipper.
//
//  Text is measured by `TextMeasurer` (ThorVG's metrics), and the lines,
//  baselines and ellipsis are placed here from those same metrics, so a
//  line is drawn where layout made room for it. The face is the file
//  `FontRegistry` resolved, loaded into Skia from the same path.
//

import NucleantSkia
import NucleantVulkan

@MainActor
public final class SkiaDisplayRenderer {

    /// The canvas to draw into, asked for on every render: a node's surface
    /// is replaced when the node is resized.
    private let target: () -> SkCanvas?

    /// Layout runs in points; the canvas is sized in backing-store pixels.
    public var scale: Double = 1

    public init<N: RenderContainerNode>(node: SkiaShaderNode<N>) {
        target = { node.canvas.surface?.canvas }
        setUpPaints()
    }

    /// Drawing into a CPU surface — what the tests read pixels back from.
    init(surface: SkRasterSurface) {
        target = { surface.getCanvas() }
        setUpPaints()
    }

    private func setUpPaints() {
        fillPaint.setStyle(.fill)
        strokePaint.setStyle(.stroke)
        tintPaint.setStyle(.fill)
        tintPaint.setBlendMode(.srcIn)
    }

    /// One of each, set per command rather than made per command — each is
    /// a Swift object over a C++ heap one.
    private let fillPaint = SkPaint()
    private let strokePaint = SkPaint()
    private let textPaint = SkPaint()
    private let imagePaint = SkPaint()
    /// The layer an SVG is faded or tinted in, and the tint laid over it.
    private let layerPaint = SkPaint()
    private let tintPaint = SkPaint()
    private let path = SkPath()

    /// Fonts by face, size and synthetic slant — what text draws with.
    private struct FontKey: Hashable {
        let family: String?
        let size: Double
        let slanted: Bool
    }
    private var fonts: [FontKey: SkFont] = [:]

    /// Images drawn by the last render, by the `RasterImage` they were made
    /// from. The source is held with its image, so its identifier stays its
    /// own; whatever a render does not draw is dropped after it.
    private var images: [ObjectIdentifier: (source: RasterImage, image: SkImage)] = [:]
    private var imagesDrawn: Set<ObjectIdentifier> = []

    /// Replace the canvas contents with `list`.
    public func render(_ list: DisplayList) {
        guard let canvas = begin() else { return }
        canvas.save()
        canvas.scale(Float(scale))
        emit(list, on: canvas)
        canvas.restore()
        end()
    }

    /// Replace the canvas contents with `list` drawn as a layer: shifted so
    /// `origin` (points) lands at the canvas corner, and flipped so y runs
    /// upwards over a canvas `flipHeight` pixels tall — the space a
    /// `.shader` effect samples it in.
    func render(_ list: DisplayList, origin: Point?, flipHeight: Int) {
        guard let origin else {
            render(list)
            return
        }
        guard let canvas = begin() else { return }
        canvas.save()
        // Pixel space, before `scale`: translate by the origin, then
        // y' = height - y.
        canvas.concat(SkMatrix(
            scaleX: 1, skewX: 0, transX: Float(-origin.x * scale),
            skewY: 0, scaleY: -1, transY: Float(Double(flipHeight) + origin.y * scale)
        ))
        canvas.scale(Float(scale))
        emit(list, on: canvas)
        canvas.restore()
        end()
    }

    /// Replace the canvas contents with several lists side by side, each at
    /// its own pixel offset — the painter's batch, copied out region by
    /// region into the per-view images.
    func render(packed items: [(list: DisplayList, x: Int, y: Int)]) {
        guard let canvas = begin() else { return }
        for item in items {
            canvas.save()
            canvas.translate(dx: Float(item.x), dy: Float(item.y))
            canvas.scale(Float(scale))
            emit(item.list, on: canvas)
            canvas.restore()
        }
        end()
    }

    /// The canvas, emptied, with no transform or clip left over.
    private func begin() -> SkCanvas? {
        guard let canvas = target() else { return nil }
        canvas.restoreToCount(1)
        canvas.resetMatrix()
        canvas.clear(SIMD4<Float>(0, 0, 0, 0))
        imagesDrawn.removeAll(keepingCapacity: true)
        return canvas
    }

    /// Drop the images this render did not draw — usually none.
    private func end() {
        guard images.count > imagesDrawn.count else { return }
        for key in Array(images.keys) where !imagesDrawn.contains(key) {
            images[key] = nil
        }
    }

    private func emit(_ list: DisplayList, on canvas: SkCanvas) {
        for command in list.commands {
            switch command {
            case .shape(let draw):
                emit(draw, on: canvas)
            case .text(let draw):
                emit(draw, on: canvas)
            case .image(let draw):
                emit(draw, on: canvas)
            case .svg(let draw):
                emit(draw, on: canvas)
            case .canvas(let draw):
                emit(draw, on: canvas)
            }
        }
    }

    // MARK: - Canvas views

    /// A `Canvas` view: the node's own canvas, handed over at the view's
    /// origin, cut to its frame, under its clip and transform.
    private func emit(_ draw: CanvasDraw, on canvas: SkCanvas) {
        let saved = canvas.save()
        begin(on: canvas, transform: draw.transform, clip: draw.clip, cornerRadius: draw.clipCornerRadius, transformedClips: draw.transformedClips)
        canvas.translate(dx: Float(draw.frame.minX), dy: Float(draw.frame.minY))
        canvas.clipRect(pos: .zero, size: SIMD2(Float(draw.frame.width), Float(draw.frame.height)), doAntiAlias: true)
        if draw.opacity < 1 {
            canvas.saveLayerAlphaf(Float(max(draw.opacity, 0)))
        }
        draw.drawing.run(canvas.base)
        canvas.restoreToCount(saved)
    }

    // MARK: - Shapes

    private func emit(_ draw: ShapeDraw, on canvas: SkCanvas) {
        let fill = draw.fill.flatMap { $0.isClear ? nil : $0 }
        let stroke = draw.stroke.flatMap { $0.isClear || draw.strokeStyle.lineWidth <= 0 ? nil : $0 }
        guard fill != nil || stroke != nil else { return }

        // A rect, a rounded rect or an ellipse alone — a background, a
        // border, a control's track and thumb — is drawn as one; anything
        // else through the path.
        let primitive = draw.path.elements.count == 1 ? draw.path.elements[0] : nil
        switch primitive {
        case .rect?, .ellipse?:
            break
        default:
            path.reset()
            append(draw.path, to: path)
        }

        canvas.save()
        begin(on: canvas, transform: draw.transform, clip: draw.clip, cornerRadius: draw.clipCornerRadius, transformedClips: draw.transformedClips)
        if let origin = draw.origin {
            canvas.translate(dx: Float(origin.x), dy: Float(origin.y))
        }

        func drawShape(with paint: SkPaint) {
            switch primitive {
            case .rect(let rect, let radiusX, let radiusY)?:
                if radiusX > 0 || radiusY > 0 {
                    canvas.drawRRect(pos: rect.origin, size: rect.size, radius: SIMD2(radiusX, radiusY), paint: paint)
                } else {
                    canvas.drawRect(pos: rect.origin, size: rect.size, paint: paint)
                }
            case .ellipse(let center, let radiusX, let radiusY)?:
                let radius = SIMD2(radiusX, radiusY)
                canvas.drawOval(pos: center - radius, size: radius * 2, paint: paint)
            default:
                canvas.drawPath(path, paint: paint)
            }
        }

        if let fill {
            apply(fill, to: fillPaint, bounds: draw.bounds)
            drawShape(with: fillPaint)
        }
        if let stroke {
            let style = draw.strokeStyle
            let paint = strokePaint
            paint.setStrokeWidth(style.lineWidth)
            paint.setStrokeCap(skiaCap(style.lineCap))
            paint.setStrokeJoin(skiaJoin(style.lineJoin))
            if style.dash.isEmpty {
                paint.clearPathEffect()
            } else {
                // Skia wants on/off pairs; an odd pattern repeats to make them.
                var intervals = style.dash.map { Float($0) }
                if intervals.count % 2 == 1 { intervals += intervals }
                if let dash = SkDashPathEffect.make(intervals: intervals, phase: Float(style.dashPhase)) {
                    paint.setPathEffect(dash)
                } else {
                    paint.clearPathEffect()
                }
            }
            apply(stroke, to: paint, bounds: draw.bounds)
            drawShape(with: paint)
        }

        if let fill {
            emitEmbedded(draw.path, fill: fill, on: canvas)
        }

        canvas.restore()
    }

    /// The text and images in a path, painted with its fill: text in the
    /// fill's color, an image faded by its alpha. Inside the shape's own
    /// save, so its clip and transform already hold.
    private func emitEmbedded(_ path: Path, fill: ShapeStyle, on canvas: SkCanvas) {
        let color = fill.flatColor
        for element in path.elements {
            switch element {
            case .text(let string, let origin, let font):
                emit(TextDraw(
                    string: string,
                    frame: Rect(origin: origin, size: Path.textExtent(string, font: font)),
                    font: font,
                    color: color,
                    wraps: false
                ), on: canvas)
            case .image(let image, let rect):
                emit(ImageDraw(image: image, frame: rect, opacity: Double(color.alpha)), on: canvas)
            default:
                break
            }
        }
    }

    private func append(_ path: Path, to skPath: SkPath) {
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
                let pos = rect.origin
                let size = rect.size
                if radiusX > 0 || radiusY > 0 {
                    skPath.addRRect(pos: pos, size: size, radius: SIMD2(radiusX, radiusY))
                } else {
                    skPath.addRect(pos: pos, size: size)
                }
            case .ellipse(let center, let radiusX, let radiusY):
                let radius = SIMD2(radiusX, radiusY)
                skPath.addOval(pos: center - radius, size: radius * 2)
            case .text, .image:
                // Not geometry: drawn after the path, by `emitEmbedded`.
                break
            }
        }
    }

    private func apply(_ style: ShapeStyle, to paint: SkPaint, bounds: Rect) {
        switch style {
        // A display list holds styles resolved for their scheme as they were
        // recorded; a dynamic one that got past that draws its light color.
        case .color(let color), .dynamic(light: let color, dark: _):
            let (r, g, b, a) = color.rgba8
            paint.clearShader()
            paint.setColor(SIMD4(r, g, b, a))
        case .linearGradient(let gradient, let startPoint, let endPoint):
            let start = startPoint.resolved(in: bounds)
            let end = endPoint.resolved(in: bounds)
            let (colors, positions) = stops(gradient)
            paint.setColor(SIMD4<UInt8>(0, 0, 0, 255))
            if let shader = SkGradientShader.makeLinear(
                from: SIMD2<Float>(start),
                to: SIMD2<Float>(end),
                colors: colors, positions: positions
            ) {
                paint.setShader(shader)
            } else {
                paint.clearShader()
            }
        case .radialGradient(let gradient, let center, let startRadius, let endRadius):
            let origin = center.resolved(in: bounds)
            let point = SIMD2<Float>(origin)
            let (colors, positions) = stops(gradient)
            paint.setColor(SIMD4<UInt8>(0, 0, 0, 255))
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

    /// The stops as Skia takes them — through `rgba8`, so a gradient comes
    /// out in the same 8-bit steps the ThorVG renderer hands over.
    private func stops(_ gradient: Gradient) -> (colors: [SIMD4<Float>], positions: [Float]) {
        var colors: [SIMD4<Float>] = []
        var positions: [Float] = []
        for stop in gradient.stops {
            let (r, g, b, a) = stop.color.rgba8
            colors.append(SIMD4<Float>(Float(r), Float(g), Float(b), Float(a)) / 255)
            positions.append(Float(stop.location))
        }
        return (colors, positions)
    }

    // MARK: - Text

    /// ThorVG takes a text size in points at 96 DPI and draws it at
    /// `size × 96/72` user units; `TextMeasurer` measures with ThorVG, so
    /// every text box is sized for that. Skia's size is the em height
    /// itself, so it is given the same factor — the glyphs then fill the
    /// box layout made for them.
    static let thorPointScale = 96.0 / 72.0

    /// Faces loaded into Skia, by the family name `FontRegistry` resolved.
    private static var typefaces: [String: SkTypeface] = [:]
    /// The platform's default face, for a font nothing resolved for.
    private static var defaultTypeface: SkTypeface?

    private func emit(_ draw: TextDraw, on canvas: SkCanvas) {
        guard !draw.string.isEmpty else { return }
        let family = FontRegistry.resolve(draw.font)
        // No italic face found: a synthetic shear still reads as italic.
        let slanted = draw.font.isItalic && !(family?.contains("Italic") ?? false)
        let font = self.font(family: family, size: draw.font.size, slanted: slanted)

        var lines = draw.string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if draw.wraps, draw.lineLimit != 1 {
            lines = TextMeasurer.wrap(draw.string, font: draw.font, maxWidth: draw.frame.width, lineLimit: draw.lineLimit)
        }
        if let limit = draw.lineLimit, limit > 0, lines.count > limit {
            lines = Array(lines.prefix(limit))
        }
        // Ellipsis only when layout found the string too wide — a box
        // measured to exactly fit its text loses nothing.
        if draw.isTruncated, let first = lines.first {
            lines = [ellipsized(first, toFit: draw.frame.width, font: font, family: family, style: draw.font)]
        }

        let paint = textPaint
        let (r, g, b, a) = draw.color.rgba8
        paint.setColor(SIMD4(r, g, b, a))

        canvas.save()
        begin(on: canvas, transform: draw.transform, clip: draw.clip, cornerRadius: draw.clipCornerRadius, transformedClips: draw.transformedClips)
        // The first baseline an ascent below the box's top, the rest a line
        // height and the line spacing apart — the metrics layout sized the
        // box with.
        let metrics = TextMeasurer.lineMetrics(for: draw.font)
        let step = metrics.lineHeight + draw.lineSpacing
        let factor = alignFactor(draw.alignment)
        for (index, line) in lines.enumerated() where !line.isEmpty {
            let y = draw.frame.minY + metrics.ascent + Double(index) * step
            let spacing = draw.letterSpacing + (index == lines.count - 1 ? draw.lastLineTightening : 0)
            let runs = self.runs(of: line, in: font, family: family, style: draw.font)
            if spacing == 0 {
                let widths = runs.map { Double($0.font.measureText($0.text)) }
                let width = widths.reduce(0, +)
                let x = draw.frame.minX + (draw.frame.width - width) * factor
                var pen = x
                for (run, advance) in zip(runs, widths) {
                    canvas.drawString(run.text, x: Float(pen), y: Float(y), font: run.font, paint: paint)
                    pen += advance
                }
                decorate(draw, from: x, to: x + width, baseline: y, on: canvas)
            } else {
                let spread = spaced(runs, by: spacing)
                let x = draw.frame.minX + (draw.frame.width - spread.advance) * factor
                for piece in spread.pieces {
                    canvas.drawGlyphs(piece.glyphs, positions: piece.positions, origin: SIMD2(Float(x), Float(y)), font: piece.font, paint: paint)
                }
                decorate(draw, from: x, to: x + spread.advance - spacing, baseline: y, on: canvas)
            }
        }
        canvas.restore()
    }

    /// `line` in runs of one font each: `font`, or — for a character its
    /// face has no glyph for — the font of the face the platform falls back
    /// to for it, as the measurer measured it.
    private func runs(of line: String, in font: SkFont, family: String?, style: Font) -> [(text: String, font: SkFont)] {
        let fallback = FontFallback.shared
        if line.utf8.allSatisfy({ $0 < 0x80 }), fallback.coversASCII(family: family) { return [(line, font)] }
        var runs: [(text: String, font: SkFont)] = []
        for character in line {
            let face = fallback.font(
                for: character, family: family, size: style.size, bold: style.weight.isBoldFace, italic: style.isItalic
            ) ?? font
            if let last = runs.last, last.font === face {
                runs[runs.count - 1].text.append(character)
            } else {
                runs.append((String(character), face))
            }
        }
        return runs
    }

    /// The runs' glyphs placed a character at a time with `spacing` after
    /// each — a piece of glyphs for each run, in its font — and the advance
    /// of the whole, the last spacing included, as layout measured it.
    private func spaced(
        _ runs: [(text: String, font: SkFont)], by spacing: Double
    ) -> (pieces: [(font: SkFont, glyphs: [UInt16], positions: [SIMD2<Float>])], advance: Double) {
        var pieces: [(font: SkFont, glyphs: [UInt16], positions: [SIMD2<Float>])] = []
        var pen = 0.0
        for run in runs {
            var glyphs: [UInt16] = []
            var positions: [SIMD2<Float>] = []
            for character in run.text {
                let ids = run.font.textToGlyphs(String(character))
                for (id, width) in zip(ids, run.font.getWidths(ids)) {
                    glyphs.append(id)
                    positions.append(SIMD2(Float(pen), 0))
                    pen += Double(width)
                }
                pen += spacing
            }
            pieces.append((run.font, glyphs, positions))
        }
        return (pieces, pen)
    }

    /// One line's underline and strikethrough, from `start` to `end` along
    /// its baseline, each in its own color or the text's.
    private func decorate(_ draw: TextDraw, from start: Double, to end: Double, baseline: Double, on canvas: SkCanvas) {
        guard draw.underline != nil || draw.strikethrough != nil, end > start else { return }
        let metrics = TextMeasurer.decorationMetrics(for: draw.font)
        let paint = textPaint
        for (style, offset) in [(draw.underline, metrics.underline), (draw.strikethrough, metrics.strikethrough)] {
            guard let style else { continue }
            let (r, g, b, a) = (style.color ?? draw.color).rgba8
            paint.setColor(SIMD4(r, g, b, a))
            let top = baseline + offset - metrics.thickness / 2
            for dash in TextMeasurer.decorationDashes(length: end - start, thickness: metrics.thickness, pattern: style.pattern) {
                canvas.drawRect(
                    x: Float(start + dash.start), y: Float(top),
                    w: Float(dash.end - dash.start), h: Float(metrics.thickness),
                    paint: paint
                )
            }
        }
        let (r, g, b, a) = draw.color.rgba8
        paint.setColor(SIMD4(r, g, b, a))
    }

    private func font(family: String?, size: Double, slanted: Bool) -> SkFont {
        let key = FontKey(family: family, size: size, slanted: slanted)
        if let font = fonts[key] { return font }
        let font = SkFont(typeface(for: family), size: Float(size * Self.thorPointScale))
        font.setSubpixel(true)
        font.setEdging(.antiAlias)
        // Unhinted, as ThorVG draws and the layout measures. Where Skia reads
        // glyphs through FreeType (the browser, Linux, Android) its default
        // hinting rounds every advance to a whole pixel, and a word drifts
        // off its measured width a pixel every few letters.
        font.setHinting(.none)
        if slanted { font.setSkewX(-0.2) }
        fonts[key] = font
        return font
    }

    private func typeface(for family: String?) -> SkTypeface? {
        if let family {
            if let loaded = Self.typefaces[family] { return loaded }
            if let path = FontRegistry.path(ofResolved: family), let made = SkFontMgr.makeFromFile(path) {
                Self.typefaces[family] = made
                return made
            }
        }
        if Self.defaultTypeface == nil {
            Self.defaultTypeface = SkFontMgr.matchFamilyStyle(nil)
        }
        return Self.defaultTypeface
    }

    /// `line` cut short with a trailing "…" until it fits `width`.
    private func ellipsized(_ line: String, toFit width: Double, font: SkFont, family: String?, style: Font) -> String {
        func measure(_ text: String) -> Double {
            runs(of: text, in: font, family: family, style: style).reduce(0) { $0 + Double($1.font.measureText($1.text)) }
        }
        guard measure(line) > width else { return line }
        var characters = Array(line)
        while !characters.isEmpty {
            characters.removeLast()
            while characters.last == " " { characters.removeLast() }
            let candidate = String(characters) + "…"
            if measure(candidate) <= width { return candidate }
        }
        return "…"
    }

    private func alignFactor(_ alignment: TextAlignment) -> Double {
        switch alignment {
        case .leading:  return 0
        case .center:   return 0.5
        case .trailing: return 1
        }
    }

    // MARK: - Images

    private func emit(_ draw: ImageDraw, on canvas: SkCanvas) {
        guard draw.frame.width > 0, draw.frame.height > 0, let image = skImage(for: draw.image) else { return }
        let paint = imagePaint
        paint.setAlphaf(max(0, min(1, draw.opacity)))
        canvas.save()
        begin(on: canvas, transform: draw.transform, clip: draw.clip, cornerRadius: draw.clipCornerRadius, transformedClips: draw.transformedClips)
        canvas.drawImageRect(
            image,
            pos: SIMD2<Float>(draw.frame.origin),
            size: SIMD2<Float>(draw.frame.size),
            paint: paint
        )
        canvas.restore()
    }

    /// `RasterImage`'s pixels are premultiplied ARGB words — BGRA bytes on a
    /// little-endian machine, which is Skia's `bgra8888`.
    private func skImage(for raster: RasterImage) -> SkImage? {
        let key = ObjectIdentifier(raster)
        imagesDrawn.insert(key)
        if let cached = images[key] { return cached.image }
        guard let made = SkImages.rasterFromPixmapCopy(
            raster.pixels,
            size: SIMD2(Int32(raster.width), Int32(raster.height))
        ) else { return nil }
        images[key] = (raster, made)
        return made
    }

    // MARK: - SVG

    /// The document rendered into the box it fits, scaled from its own
    /// size. Faded or tinted, it is drawn into a layer first: the tint is
    /// laid over it `srcIn`, so it shows only where the document drew, by
    /// the document's coverage, and the layer composites at the opacity.
    private func emit(_ draw: SvgDraw, on canvas: SkCanvas) {
        let box = draw.image.fittedRect(in: draw.frame)
        guard box.width > 0, box.height > 0 else { return }
        let pos = SIMD2<Float>(box.origin)
        let size = SIMD2<Float>(box.size)
        let saved = canvas.save()
        begin(on: canvas, transform: draw.transform, clip: draw.clip, cornerRadius: draw.clipCornerRadius, transformedClips: draw.transformedClips)
        // The outermost <svg> cuts what it draws to its viewport, as in a
        // browser.
        canvas.clipRect(pos: pos, size: size, doAntiAlias: true)
        if draw.tint != nil || draw.opacity < 1 {
            layerPaint.setAlphaf(Float(max(0, min(1, draw.opacity))))
            canvas.saveLayer(pos: pos, size: size, paint: layerPaint)
        }
        canvas.save()
        canvas.translate(pos)
        canvas.scale(Float(box.width / draw.image.size.width))
        draw.image.document.render(canvas)
        canvas.restore()
        if let tint = draw.tint {
            apply(tint, to: tintPaint, bounds: draw.frame)
            canvas.drawRect(pos: pos, size: size, paint: tintPaint)
        }
        canvas.restoreToCount(saved)
    }

    // MARK: - Shared head

    /// Clip first, in the canvas's space, then the command's own transform —
    /// the clip does not move with what it clips. A transformed clip is cut
    /// under its own transform. The caller saves and restores around it.
    private func begin(on canvas: SkCanvas, transform: Transform, clip: Rect?, cornerRadius: Double, transformedClips: [TransformedClip]) {
        if let clip {
            clipRect(clip, cornerRadius: cornerRadius, on: canvas)
        }
        if !transformedClips.isEmpty {
            let base = canvas.getTotalMatrix()
            for turned in transformedClips {
                canvas.concat(matrix(turned.transform))
                clipRect(turned.rect, cornerRadius: turned.cornerRadius, on: canvas)
                canvas.setMatrix(base)
            }
        }
        if !transform.isIdentity {
            canvas.concat(matrix(transform))
        }
    }

    private func clipRect(_ clip: Rect, cornerRadius: Double, on canvas: SkCanvas) {
        // `.clipShape(Capsule())` asks for an unbounded radius, meaning
        // "as round as this box allows" — resolvable only here.
        let radius = min(cornerRadius, min(clip.width, clip.height) / 2)
        let pos = clip.origin
        let size = clip.size
        if radius > 0 {
            canvas.clipRRect(pos: pos, size: size, radius: SIMD2(radius, radius), doAntiAlias: true)
        } else {
            canvas.clipRect(pos: pos, size: size, doAntiAlias: true)
        }
    }

    private func matrix(_ transform: Transform) -> SkMatrix {
        SkMatrix(
            scaleX: Float(transform.e11), skewX: Float(transform.e12), transX: Float(transform.e13),
            skewY: Float(transform.e21), scaleY: Float(transform.e22), transY: Float(transform.e23)
        )
    }

    private func skiaCap(_ cap: LineCap) -> SkStrokeCap {
        switch cap {
        case .butt:   return .butt
        case .round:  return .round
        case .square: return .square
        }
    }

    private func skiaJoin(_ join: LineJoin) -> SkStrokeJoin {
        switch join {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}
