//
//  RosettePainter.swift
//  Rosettes
//
//  The rosette drawn with Skia itself: a `SkiaRenderContext` handed the
//  canvas the window's views are drawn on, at the drawing's corner, cut to
//  its frame. The sheet is a radial-gradient fill, the guides dashed
//  circles (an `SkPathEffect`), every line an `SkPath` stroked with a
//  sweep-gradient `SkShader`, and where lines cross they add up (`.plus`) or
//  darken (`.multiply`) as the ink says.
//
//  It reads the design in `update`, so the view depends on what it read:
//  moving a slider, or the engraving ticking on, draws it again — and
//  nothing else does. The lines of a layer are built once for its shape
//  and size, and kept; only the line being engraved is traced each time.
//

import Foundation
import NucleantSkia
import NucleantUI

@MainActor
final class RosettePainter: @MainActor SkiaRenderContext {
    unowned let design: Design

    private let sheet = SkPaint()
    private let guide = SkPaint()
    private let stroke = SkPaint()

    /// What a layer's lines are built from: a change to any of it builds
    /// them again.
    private struct Shape: Equatable {
        let lines: Int
        let petals: Int
        let radius: Double
        let depth: Double
        let spread: Double
        let center: SIMD2<Float>
        let scale: Float

        init(_ layer: Layer, center: SIMD2<Float>, scale: Float) {
            lines = layer.lines
            petals = layer.petals
            radius = layer.radius
            depth = layer.depth
            spread = layer.spread
            self.center = center
            self.scale = scale
        }
    }

    /// Every line of a layer, built for its shape.
    private var built: [Layer.ID: (shape: Shape, lines: [SkPath])] = [:]

    /// The sweep of ink a layer's lines are stroked with, for its hue.
    private struct InkKey: Equatable {
        let hue: Double
        let paper: Paper
        let center: SIMD2<Float>
    }
    private var inks: [Layer.ID: (key: InkKey, shader: SkShader)] = [:]

    private struct SheetKey: Equatable {
        let paper: Paper
        let size: SIMD2<Float>
    }
    private var sheetShader: (key: SheetKey, shader: SkShader)?

    init(design: Design) {
        self.design = design
    }

    func onAppear(context: borrowing SkCanvas, size: SIMD2<Float>) {
        sheet.setStyle(.fill)
        sheet.setDither(true)
        guide.setAntiAlias(true)
        guide.setStyle(.stroke)
        guide.setStrokeWidth(0.75)
        if let dashes = SkDashPathEffect.make(intervals: [2, 5]) {
            guide.setPathEffect(dashes)
        }
        stroke.setAntiAlias(true)
        stroke.setStyle(.stroke)
        stroke.setStrokeCap(.round)
        stroke.setStrokeJoin(.round)
    }

    func update(context: borrowing SkCanvas, size: SIMD2<Float>) {
        let center = size / 2
        let scale = min(size.x, size.y) / 2 * 0.94
        let paper = design.paper
        let layers = design.layers.filter(\.isVisible)

        drawSheet(on: context, size: size, center: center, paper: paper)

        if design.showsGuides {
            let tone: SIMD4<Float> = paper == .cream ? SIMD4(0.35, 0.25, 0.1, 0.35) : SIMD4(1, 1, 1, 0.22)
            guide.setColor4f(tone)
            for layer in layers {
                context.drawCircle(center: center, radius: Float(layer.radius) * scale, paint: guide)
            }
        }

        // Light ink adds up on a dark sheet; dark ink darkens a light one.
        switch (design.ink, paper) {
        case (.ink, _):
            stroke.setBlendMode(.srcOver)
            stroke.setAlphaf(0.9)
        case (.glow, .cream):
            stroke.setBlendMode(.multiply)
            stroke.setAlphaf(0.55)
        case (.glow, _):
            stroke.setBlendMode(.plus)
            stroke.setAlphaf(0.45)
        }

        // The engraving runs through every layer's lines in turn.
        let total = layers.reduce(0) { $0 + $1.lines }
        var left = design.engraved * Double(total)
        for layer in layers {
            guard left > 0 else { break }
            stroke.setStrokeWidth(Float(layer.width))
            if let shader = ink(for: layer, paper: paper, center: center) {
                stroke.setShader(shader)
            }
            let lines = self.lines(of: layer, center: center, scale: scale)
            let whole = min(layer.lines, Int(left))
            for line in lines.prefix(whole) {
                context.drawPath(line, paint: stroke)
            }
            let part = left - Double(whole)
            if whole < layer.lines, part > 0 {
                let line = SkPath()
                trace(layer, line: whole, upTo: part, center: center, scale: scale, into: line)
                context.drawPath(line, paint: stroke)
            }
            left -= Double(layer.lines)
        }

        // Layers gone take what was kept for them.
        if built.count > layers.count {
            built = built.filter { id, _ in layers.contains { $0.id == id } }
            inks = inks.filter { id, _ in layers.contains { $0.id == id } }
        }
    }

    // MARK: - Pieces

    private func drawSheet(on canvas: borrowing SkCanvas, size: SIMD2<Float>, center: SIMD2<Float>, paper: Paper) {
        let key = SheetKey(paper: paper, size: size)
        if sheetShader?.key != key {
            let colors = paper.colors
            let shader = SkGradientShader.makeRadial(
                center: center,
                radius: (size.x * size.x + size.y * size.y).squareRoot() / 2,
                colors: [SIMD4(SIMD3<Float>(colors.center), 1), SIMD4(SIMD3<Float>(colors.edge), 1)]
            )
            sheetShader = shader.map { (key, $0) }
        }
        if let shader = sheetShader?.shader {
            sheet.setShader(shader)
        }
        canvas.drawRect(pos: .zero, size: size, paint: sheet)
    }

    /// The layer's ink: its hue swinging a little either way round the
    /// rosette, so the lines shimmer as they turn.
    private func ink(for layer: Layer, paper: Paper, center: SIMD2<Float>) -> SkShader? {
        let key = InkKey(hue: layer.hue, paper: paper, center: center)
        if let kept = inks[layer.id], kept.key == key { return kept.shader }
        let brightness = paper == .cream ? 0.55 : 1.0
        let saturation = paper == .cream ? 0.85 : 0.6
        let colors = [-0.05, 0.05, -0.05, 0.05, -0.05].map { shift in
            SIMD4(SIMD3<Float>(inkColor(hue: layer.hue + shift + 1, saturation: saturation, brightness: brightness)), 1)
        }
        guard let shader = SkGradientShader.makeSweep(center: center, colors: colors) else { return nil }
        inks[layer.id] = (key, shader)
        return shader
    }

    /// Every line of `layer`, built for its shape the first time, kept after.
    private func lines(of layer: Layer, center: SIMD2<Float>, scale: Float) -> [SkPath] {
        let shape = Shape(layer, center: center, scale: scale)
        if let kept = built[layer.id], kept.shape == shape { return kept.lines }
        let lines = (0..<layer.lines).map { index in
            let path = SkPath()
            trace(layer, line: index, upTo: 1, center: center, scale: scale, into: path)
            return path
        }
        built[layer.id] = (shape, lines)
        return lines
    }

    /// Line `index` of `layer` into `path`, `fraction` of the way round: a
    /// circle of the layer's radius swinging `depth` in and out `petals`
    /// times, turned by its share of the spread.
    private func trace(_ layer: Layer, line index: Int, upTo fraction: Double, center: SIMD2<Float>, scale: Float, into path: SkPath) {
        let petals = Double(layer.petals)
        let turn = 2 * Double.pi / petals * layer.spread * Double(index) / Double(max(layer.lines, 1))
        let segments = max(180, min(1440, layer.petals * 48))
        let last = Int((Double(segments) * fraction).rounded(.up))
        for step in 0...last {
            let theta = 2 * Double.pi * Double(step) / Double(segments)
            let r = (layer.radius + layer.depth * sin(petals * theta)) * Double(scale)
            let point = center + SIMD2<Float>(Float(r * cos(theta + turn)), Float(r * sin(theta + turn)))
            if step == 0 {
                path.moveTo(point)
            } else {
                path.lineTo(point)
            }
        }
        if fraction >= 1 { path.close() }
    }
}
