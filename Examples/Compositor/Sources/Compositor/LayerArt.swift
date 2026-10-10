//
//  LayerArt.swift
//  Compositor
//
//  What a layer draws. An ordinary view tree, with nothing in it that knows
//  it is going into a texture — which is the point: `renderTexture` takes any
//  tree, and the same tree goes to the CPU exporter through `renderImage`.
//
//  Drawn on black with its own alpha, because the shader composites it over
//  what is beneath: a layer's transparent part is where the stack below shows
//  through.
//
//  Every artwork takes its colours from a `LayerPalette` rather than naming
//  any, so one slider re-tints the whole thing and switching the tone from a
//  hue wheel to a black-to-white ramp costs nothing per artwork.
//

import Foundation
import NucleantUI

@View
struct LayerArt {
    let artwork: LayerArtwork
    let palette: LayerPalette
    let detail: Double

    var body: some View {
        switch artwork {
        case .wash:    Wash(palette: palette, detail: detail)
        case .rings:   Rings(palette: palette, detail: detail)
        case .bars:    Bars(palette: palette, detail: detail)
        case .grid:    Grid(palette: palette, detail: detail)
        case .label:   Label(palette: palette, detail: detail)
        case .stripes: Stripes(palette: palette, detail: detail)
        case .dots:    Dots(palette: palette, detail: detail)
        case .burst:   Burst(palette: palette, detail: detail)
        case .waves:   Waves(palette: palette, detail: detail)
        }
    }
}

// MARK: - Colour

/// A layer's colours: a tone, and the one slider read under it.
///
/// Every artwork asks for a colour by *position* — 0 for its first element,
/// 1 for its last — and never by hue or by grey level. That is what lets the
/// same tree be a hue fan or a black-to-white ramp without a branch anywhere
/// in it.
struct LayerPalette: Hashable {
    let tone: LayerTone
    /// The slider: a hue angle under `.colour`, where the ramp starts under
    /// `.grey`.
    let value: Double

    func tint(_ position: Double = 0, alpha: Double = 1) -> Color {
        switch tone {
        case .colour:
            // The slider is the hue; the elements fan out about a fifth of
            // the wheel from it, which stays within one family of colours.
            return Self.wheel(value + position * 0.22, alpha: alpha)
        case .grey:
            // The slider lifts the whole ramp, and the elements run from
            // there towards white — so a layer is dark-on-light or
            // light-on-dark depending only on where the slider is.
            let level = min(1, max(0, 0.06 + value * 0.46 + position * 0.52))
            return Color(white: level, opacity: alpha)
        }
    }

    /// A colour from a hue in 0…1, lifted off full saturation so the blend
    /// modes have somewhere to go.
    private static func wheel(_ hue: Double, alpha: Double) -> Color {
        let h = (hue - hue.rounded(.down)) * 6
        let section = Int(h) % 6
        let f = h - Double(Int(h))
        let (r, g, b): (Double, Double, Double)
        switch section {
        case 0: (r, g, b) = (1, f, 0)
        case 1: (r, g, b) = (1 - f, 1, 0)
        case 2: (r, g, b) = (0, 1, f)
        case 3: (r, g, b) = (0, 1 - f, 1)
        case 4: (r, g, b) = (f, 0, 1)
        default: (r, g, b) = (1, 0, 1 - f)
        }
        return Color(
            red: 0.15 + r * 0.85,
            green: 0.15 + g * 0.85,
            blue: 0.15 + b * 0.85,
            opacity: alpha
        )
    }
}

// MARK: - The artworks

@View
private struct Wash {
    let palette: LayerPalette
    let detail: Double

    var body: some View {
        Rectangle()
            .fill(.linearGradient(
                colors: [palette.tint(0, alpha: 0.55), palette.tint(detail, alpha: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
    }
}

@View
private struct Rings {
    let palette: LayerPalette
    let detail: Double

    private var count: Int { 3 + Int(detail * 8) }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let t = Double(index) / Double(max(1, count - 1))
                Circle()
                    .stroke(palette.tint(t, alpha: 0.9), lineWidth: 2 + 6 * (1 - t))
                    .frame(width: 60 + t * 260, height: 60 + t * 260)
            }
        }
    }
}

@View
private struct Bars {
    let palette: LayerPalette
    let detail: Double

    private var count: Int { 6 + Int(detail * 18) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                let t = Double(index) / Double(max(1, count - 1))
                // A deterministic wobble, so the layer looks like a readout
                // without pulling in a clock the texture would never see.
                let height = 0.25 + 0.7 * abs(sin(t * 7.3 + detail * 4))
                Capsule()
                    .fill(palette.tint(t, alpha: 0.95))
                    .frame(maxWidth: .infinity)
                    .frame(height: canvasSize.height * height)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
    }
}

@View
private struct Grid {
    let palette: LayerPalette
    let detail: Double

    private var columns: Int { 4 + Int(detail * 10) }

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<columns, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<columns, id: \.self) { column in
                        let on = (row * 3 + column * 5) % 4 != 0
                        let t = Double(column) / Double(max(1, columns - 1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.tint(t, alpha: on ? 0.85 : 0.12))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(12)
    }
}

@View
private struct Label {
    let palette: LayerPalette
    let detail: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text("LAYER")
                .font(.system(size: 18 + detail * 14, weight: .bold))
                .foregroundStyle(palette.tint(0, alpha: 0.95))
            Text("composited on the GPU")
                .font(.system(size: 11 + detail * 5))
                .foregroundStyle(palette.tint(0.35, alpha: 0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

/// Vertical bars at alternating widths — the plainest thing a difference or
/// a multiply has to work on, and the easiest to read the result of.
@View
private struct Stripes {
    let palette: LayerPalette
    let detail: Double

    private var count: Int { 4 + Int(detail * 16) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                let t = Double(index) / Double(max(1, count - 1))
                Rectangle()
                    .fill(palette.tint(t, alpha: index.isMultiple(of: 2) ? 0.9 : 0.25))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// A field of dots whose size walks across the frame. Under `.grey` and a
/// multiply it is a grain pass over whatever is beneath.
@View
private struct Dots {
    let palette: LayerPalette
    let detail: Double

    private var columns: Int { 5 + Int(detail * 13) }
    private var rows: Int { max(3, columns * 2 / 3) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        // Big in one corner, small in the other, with a
                        // ripple across the middle.
                        let u = Double(column) / Double(max(1, columns - 1))
                        let v = Double(row) / Double(max(1, rows - 1))
                        let size = 0.2 + 0.75 * abs(sin(u * 3.1 + v * 2.2 + detail * 3))
                        Circle()
                            .fill(palette.tint((u + v) / 2, alpha: 0.9))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .relativeSize(width: size, height: size)
                    }
                }
            }
        }
        .padding(6)
    }
}

/// Spokes from the middle. One shape rotated N times, which is the cheapest
/// way to a radial pattern with no path maths at all.
@View
private struct Burst {
    let palette: LayerPalette
    let detail: Double

    private var count: Int { 6 + Int(detail * 26) }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let t = Double(index) / Double(count)
                Capsule()
                    .fill(palette.tint(t, alpha: 0.8))
                    .frame(width: 3 + detail * 7, height: canvasSize.height * 0.95)
                    .rotationEffect(.degrees(t * 180))
            }
        }
    }
}

/// Sine curves as a `PathShape` — the one artwork that builds its own path,
/// so the export has something a stroke-heavy tree does to prove.
@View
private struct Waves {
    let palette: LayerPalette
    let detail: Double

    private var count: Int { 3 + Int(detail * 9) }

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                let t = Double(index) / Double(max(1, count - 1))
                PathShape { size in
                    Path { path in
                        let amplitude = size.height * (0.06 + 0.16 * detail)
                        let middle = size.height * (0.12 + 0.76 * t)
                        let steps = max(8, Int(size.width / 4))
                        for step in 0...steps {
                            let x = size.width * Double(step) / Double(steps)
                            let phase = Double(step) / Double(steps) * 6.283 * (1 + detail * 2)
                            let y = middle + sin(phase + t * 2.4) * amplitude
                            if step == 0 {
                                path.move(to: Point(x: x, y: y))
                            } else {
                                path.addLine(to: Point(x: x, y: y))
                            }
                        }
                    }
                }
                .stroke(palette.tint(t, alpha: 0.9), lineWidth: 2 + detail * 3)
            }
        }
    }
}
