//
//  CanvasEffects.swift
//  NucleantUIDemo
//
//  `.shader` over a `ThorCanvasRender`. A canvas view draws into a VkImage
//  of its own, and under an effect that image is the shader's input —
//  `layer(uv)` reads it upright, as it does any other view. The same
//  landscape three times: as it is, under a compute effect, and under a
//  vertex + fragment pair.
//

import NucleantUI
import NucleantThorVG
import Observation

/// Where the sun stands, as a fraction of the canvas width. Moved by the
/// button; every painting reads it in `update`, so a move redraws each
/// canvas and re-runs the effect over it.
@MainActor @Observable
final class SunPosition {
    private(set) var x: Double = 0.25

    func advance() {
        x = x >= 0.75 ? 0.25 : x + 0.25
    }
}

/// One ThorVG paint the painting keeps and changes in place.
final class LandscapePaint: ThorShape {
    var base: Tvg_Paint

    init() {
        base = tvg_shape_new()
        _ = tvg_paint_ref(base)
    }

    deinit {
        _ = tvg_paint_unref(base, true)
    }
}

/// Sky, sun and ground: up is unmistakable. The paths are built for a size
/// and rebuilt only when it changes; the sun moves by `translate`.
@MainActor
final class Landscape: @MainActor ThorRenderContext {
    let sun: SunPosition
    private let sky = LandscapePaint()
    private let disc = LandscapePaint()
    private let ground = LandscapePaint()
    private var builtSize: SIMD2<Float> = .zero

    init(sun: SunPosition) {
        self.sun = sun
    }

    func onAppear(context: borrowing ThorContext, size: SIMD2<Float>) {
        context.add(shape: sky)
        context.add(shape: disc)
        context.add(shape: ground)
    }

    func update(context: borrowing ThorContext, size: SIMD2<Float>) {
        if size != builtSize {
            builtSize = size
            sky.reset()
            _ = sky.append_rect(x: 0, y: 0, w: size.x, h: size.y)
            _ = sky.set_fill_color(r: 92, g: 154, b: 224, a: 255)

            // Drawn at the origin and moved into place, so a move is a
            // translate rather than a new path.
            let radius = size.y * 0.16
            disc.reset()
            _ = disc.append_circle(cx: 0, cy: 0, rx: radius, ry: radius)
            _ = disc.set_fill_color(r: 255, g: 214, b: 92, a: 255)

            ground.reset()
            _ = ground.append_rect(x: 0, y: size.y * 0.7, w: size.x, h: size.y * 0.3)
            _ = ground.set_fill_color(r: 70, g: 140, b: 72, a: 255)
        }
        _ = disc.translate(x: size.x * Float(sun.x), y: size.y * 0.28)
    }
}

/// The two effects, both in PyShader.
enum CanvasEffect {
    /// Compute: a sine ripple across the canvas.
    static let ripple = ShaderFunction(pyshader: """
        def main(uv: float2, time: float) -> float4:
            p = float2(uv.x + 0.012 * sin(uv.y * 40.0 + time * 3.0), uv.y)
            return layer(p)
        """)

    /// Vertex + fragment: one quad over the view, its fragment stage a lens
    /// bulging the middle and darkening the edges.
    static let lens = ShaderFunction(pyshader: """
        QUAD = [float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
                float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)]

        class Quad:
            position: float4
            local: float2

        def vertex(vertex_index: int) -> Quad:
            quad = QUAD
            corner = quad[vertex_index]
            return Quad(position=float4(corner, 0.0, 1.0), local=corner * 0.5 + 0.5)

        def fragment(local: float2, time: float) -> float4:
            d = local - float2(0.5, 0.5)
            r = length(d)
            pull = 0.3 * (1.0 - smoothstep(0.0, 0.5, r)) * (0.75 + 0.25 * sin(time * 2.0))
            colour = layer(float2(0.5, 0.5) + d * (1.0 - pull))
            vignette = smoothstep(0.8, 0.35, r)
            return float4(colour.xyz * vignette, colour.w)
        """)
}

/// The sun and the three paintings showing it. The paintings are kept for
/// as long as the section stands: a canvas adds a painting's paints once,
/// when its node appears, and changes them in place from then on.
@MainActor
final class CanvasEffectsModel {
    let sun = SunPosition()
    let plain: Landscape
    let rippled: Landscape
    let lensed: Landscape

    init() {
        plain = Landscape(sun: sun)
        rippled = Landscape(sun: sun)
        lensed = Landscape(sun: sun)
    }
}

/// The landscape plain, under the compute effect and under the vertex +
/// fragment one — each a `ThorCanvasRender` of its own.
@View
struct CanvasEffectsSection {
    @State private var model = CanvasEffectsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A ThorCanvasRender under .shader — its own canvas image is the effect's input.")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                CanvasCard(title: "Canvas") {
                    ThorCanvasRender(context: model.plain)
                        .frame(width: 180, height: 110)
                }
                CanvasCard(title: "Compute") {
                    ThorCanvasRender(context: model.rippled)
                        .frame(width: 180, height: 110)
                        .shader(CanvasEffect.ripple)
                }
                CanvasCard(title: "Vertex + fragment") {
                    ThorCanvasRender(context: model.lensed)
                        .frame(width: 180, height: 110)
                        .shader(CanvasEffect.lens)
                }
            }

            Button("Move the sun") { model.sun.advance() }
                .tint(Palette.accent)
        }
    }
}

/// A canvas with its caption under it.
@View
struct CanvasCard<Content: View> {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            Text(title)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}
