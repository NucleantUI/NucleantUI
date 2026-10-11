//
//  TextureScreen.swift
//  NucleantUIDemo
//
//  `RenderTexture` on the GPU: the part the test target cannot reach.
//
//  Everything above the image is covered by `RenderTextureTests` headlessly —
//  the tree is driven, the display list matches `renderImage`'s, no window
//  pass is disturbed. What needs a window, and so needs this screen, is the
//  image itself: a texture shown through `tex.view()`, run through a shader
//  with `tex.shader(_:)`, mixed with a second texture as a named shader
//  input, and read back with `tex.image()` to be compared against the CPU
//  path drawing the same tree.
//

import Foundation
import NucleantUI

/// The textures this screen holds, and the readback report.
///
/// A model, not `@State` in the view: a texture is an object with GPU memory
/// behind it, and the whole point is that it outlives the views showing it.
@MainActor
@Observable
final class TextureDemo {

    static let size = Size(width: 260, height: 150)

    /// What the card says. Changing it is what `redraw` makes visible — a
    /// texture is a snapshot and re-renders for nothing else.
    private(set) var reading: Int

    let card: RenderTexture
    let dial: RenderTexture
    /// One flat colour, for the half of the readback that has a right answer
    /// to the bit: no antialiasing anywhere in it, so a single differing
    /// channel is a channel-order or layout bug rather than a rasterizer
    /// disagreeing with itself.
    let flat: RenderTexture

    /// How far the mix shader is from the card to the dial.
    var blend: Double = 0.4

    /// The last `tex.image()` vs `renderImage` comparison: the flat probe,
    /// which has to match exactly, and the card, which has antialiased edges
    /// two rasterizers are allowed to disagree about.
    private(set) var flatReport = "Not checked yet"
    private(set) var cardReport = ""

    init() {
        let reading = 62
        self.reading = reading
        card = renderTexture(size: Self.size) { TextureCard(reading: reading) }
        dial = renderTexture(size: Self.size) { TextureDial(reading: reading) }
        flat = renderTexture(size: Self.size) { Color(hex: 0x3366CC) }
    }

    func redraw() {
        reading = (reading + 17) % 100
        let reading = self.reading
        card.update { TextureCard(reading: reading) }
        dial.update { TextureDial(reading: reading) }
        flatReport = "Not checked yet"
        cardReport = ""
    }

    /// The one place the GPU and CPU paths have to agree: the texture's own
    /// pixels, read back, against `renderImage` of the same tree at the same
    /// size and scale.
    ///
    /// Reported rather than asserted, and with the spread as well as the
    /// count: the two rasterize through different ThorVG targets, so an
    /// antialiased edge differing by a step is a true answer and a tenth of
    /// the image differing is not.
    /// Run the check once, a few frames in. `tex.image()` has nothing to read
    /// until the engine has drawn the texture's canvas, so a check on the
    /// first layout pass always answers "no image yet" — which is true, and
    /// useless. Scheduled rather than awaited: this is a demo screen, and
    /// waiting on the GPU from a layout pass is the one thing `image()` says
    /// not to do.
    /// Run the check once, a few frames in. `tex.image()` has nothing to read
    /// until the engine has drawn the texture's canvas, so a check on the
    /// first layout pass always answers "no image yet" — which is true, and
    /// useless. Scheduled rather than awaited: this is a demo screen, and
    /// waiting on the GPU from a layout pass is the one thing `image()` says
    /// not to do.
    func checkWhenDrawn() {
        guard flatReport == "Not checked yet" else { return }
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            Task { @MainActor in self.check() }
        }
    }

    /// The one place the GPU and CPU paths have to agree: a texture's own
    /// pixels, read back, against `renderImage` of the same tree at the same
    /// size and scale.
    ///
    /// Two trees, because they answer different questions. The flat colour
    /// has no antialiasing in it at all, so it is exact or it is a bug — it
    /// is what caught `readback` handing back its channels in the wrong
    /// order. The card has text and a rounded bar, so its edges are two
    /// rasterizers (ThorVG's GPU target and its software one) each deciding
    /// how much of a pixel a curve covers, and a difference there is a true
    /// answer rather than a fault.
    func check() {
        guard let readFlat = flat.image() else {
            flatReport = "No image yet — the textures have not reached a frame"
            cardReport = ""
            return
        }
        let drawnFlat = renderImage(size: Self.size, scale: flat.scale) { Color(hex: 0x3366CC) }
        flatReport = "Flat colour · " + Self.compare(readFlat, drawnFlat)
        if let readCard = card.image() {
            let reading = self.reading
            let drawnCard = renderImage(size: Self.size, scale: card.scale) {
                TextureCard(reading: reading)
            }
            cardReport = "Text and shapes · " + Self.compare(readCard, drawnCard)
        }
        print("[texture] \(flatReport) / \(cardReport)")
    }

    /// How far apart two images are, and how much of the difference sits on
    /// an edge — a pixel the CPU image itself does not agree with one of its
    /// neighbours about, which is exactly where antialiasing lives.
    private static func compare(_ readback: RasterImage, _ drawn: RasterImage) -> String {
        guard readback.width == drawn.width, readback.height == drawn.height else {
            return "size mismatch: \(readback.width)×\(readback.height) read back, "
                + "\(drawn.width)×\(drawn.height) drawn"
        }
        let width = drawn.width, height = drawn.height
        var differing = 0
        var onEdge = 0
        var worst = 0
        var total = 0
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let lhs = readback.pixels[index], rhs = drawn.pixels[index]
                guard lhs != rhs else { continue }
                differing += 1
                for shift in stride(from: 0, through: 24, by: 8) {
                    let delta = abs(Int((lhs >> UInt32(shift)) & 0xFF) - Int((rhs >> UInt32(shift)) & 0xFF))
                    worst = max(worst, delta)
                    total += delta
                }
                let neighbours = [
                    x > 0 ? index - 1 : nil, x < width - 1 ? index + 1 : nil,
                    y > 0 ? index - width : nil, y < height - 1 ? index + width : nil,
                ].compactMap { $0 }
                if neighbours.contains(where: { drawn.pixels[$0] != rhs }) { onEdge += 1 }
            }
        }
        let count = max(1, width * height)
        guard differing > 0 else {
            return String(format: "%d×%d · identical to the bit", width, height)
        }
        return String(
            format: "%d×%d · %.1f%% identical · %d differ, %d of them on an antialiased edge "
                + "· worst channel Δ %d · mean Δ %.2f",
            width, height,
            Double(count - differing) / Double(count) * 100,
            differing, onEdge, worst, Double(total) / Double(count * 4)
        )
    }
}

// MARK: - The trees the textures hold

@View
struct TextureCard {
    let reading: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CARD")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Text("\(reading)%")
                .font(.system(size: 34, weight: .bold))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.track)
                    .frame(height: 8)
                Capsule()
                    .fill(Palette.accent)
                    .relativeSize(width: Double(reading) / 100)
                    .frame(height: 8)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.panel)
    }
}

@View
struct TextureDial {
    let reading: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.track, lineWidth: 14)
                .frame(width: 104, height: 104)
            Circle()
                .stroke(Palette.good, lineWidth: 14)
                .frame(width: 104, height: 104)
                .opacity(0.25 + Double(reading) / 100 * 0.75)
            Text("\(reading)")
                .font(.system(size: 26, weight: .bold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.panelHighlight)
    }
}

// MARK: - Shaders over textures

/// Two textures mixed by name. `a(uv)` and `b(uv)` are the images; `blend`
/// is an ordinary `ShaderArgument`, so dragging the slider re-dispatches
/// without recompiling anything.
@MainActor
let textureMix = ShaderFunction(pyshader: """
def main(uv: float2, blend: float, a: Texture, b: Texture) -> float4:
    pa = a(uv)
    pb = b(uv)
    edge = smoothstep(blend - 0.12, blend + 0.12, uv.x)
    return mix(pa, pb, edge)
""")

/// An effect over a texture: `layer(uv)` is the texture, exactly as it is
/// the view under `.shader(_:)`.
@MainActor
let textureRipple = ShaderFunction(pyshader: """
def main(uv: float2, time: float) -> float4:
    wave = sin(uv.y * 26.0 + time * 2.0) * 0.012
    return layer(float2(uv.x + wave, uv.y))
""")

// MARK: - Screen

@View
struct TextureScreen {
    @State private var demo = TextureDemo()

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                Text("""
                A view tree rendered into a GPU texture a model holds. Each \
                picture below borrows the same two images — nothing is drawn \
                twice.
                """)
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Section("tex.view()") {
                    HStack(alignment: .top, spacing: 14) {
                        demo.card.view()
                        demo.dial.view()
                    }
                }

                Section("tex.view().resizable()") {
                    demo.card.view().resizable()
                        .frame(maxWidth: .infinity)
                        .frame(height: 110)
                }

                Section("tex.shader(_:) — an effect over the texture") {
                    demo.card.shader(textureRipple)
                }

                Section("Shader(textures:) — both textures, mixed by name") {
                    VStack(alignment: .leading, spacing: 8) {
                        Shader(
                            textureMix,
                            arguments: [.float("blend", Float(demo.blend))],
                            textures: [.init("a", demo.card), .init("b", demo.dial)]
                        )
                        .frame(height: TextureDemo.size.height)

                        Slider(value: $demo.blend, in: 0...1) {
                            Text("Blend")
                        } minimumValueLabel: {
                            Text("card").font(.footnote).foregroundColor(.secondary)
                        } maximumValueLabel: {
                            Text("dial").font(.footnote).foregroundColor(.secondary)
                        }
                    }
                }

                Section("tex.image() against renderImage") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(demo.flatReport)
                            .font(.system(size: 12, design: .monospaced))
                        if !demo.cardReport.isEmpty {
                            Text(demo.cardReport)
                                .font(.system(size: 12, design: .monospaced))
                        }
                        HStack(spacing: 8) {
                            Button("Check") { demo.check() }
                                .tint(Palette.accent)
                            Button("Redraw both") { demo.redraw() }
                                .tint(Palette.muted)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { demo.checkWhenDrawn() }
    }
}

@View
private struct Section<Content: View> {
    let title: String
    let content: Content

    init(_ title: String, _viewID: ViewID = #viewID, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self._viewID = _viewID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(horizontal: 14, vertical: 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panelHighlight)
        .cornerRadius(12)
    }
}
