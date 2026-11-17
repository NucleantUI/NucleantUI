//
//  Cover.swift
//  Listen
//
//  Album covers, drawn rather than loaded: the album's field shaded from
//  its light colour to its deep one, its motif in ink over it, and its
//  title in the corner when the cover is big enough to read it. And the
//  app's icons, drawn the same way.
//

import NucleantUI

/// An album's cover, `size` points square.
@View
struct Cover {
    let album: Album
    let size: Double
    let showsTitle: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [album.palette.light, album.palette.deep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            if album.motif.isStroked {
                MotifShape(motif: album.motif, seed: album.id)
                    .stroke(album.palette.ink.opacity(0.6), lineWidth: max(1, size * 0.022))
            } else {
                MotifShape(motif: album.motif, seed: album.id)
                    .fill(album.palette.ink.opacity(0.55))
            }
            if showsTitle {
                VStack(alignment: .leading, spacing: size * 0.01) {
                    Text(album.title.uppercased())
                        .font(.system(size: size * 0.085, weight: .heavy))
                        .tracking(size * 0.004)
                        .lineLimit(2)
                    Text(album.artist)
                        .font(.system(size: size * 0.065, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(album.palette.ink)
                .padding(size * 0.07)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.05)))
    }
}

extension Motif {
    /// Drawn as lines rather than shapes.
    var isStroked: Bool {
        switch self {
        case .rings, .waves: true
        case .stripes, .sun, .grid, .dots: false
        }
    }
}

/// A cover's pattern, laid out in whatever rect it is given.
@View
struct MotifShape: Shape {
    let motif: Motif
    let seed: Int

    func path(in rect: Rect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let x = rect.minX, y = rect.minY
        switch motif {
        case .rings:
            let center = Point(x: x + w * 0.72, y: y + h * 0.32)
            for ring in 1...6 {
                let radius = Double(ring) * min(w, h) * 0.09
                path.addEllipse(in: Rect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
        case .stripes:
            let band = w * 0.11
            var start = -h
            while start < w {
                path.move(to: Point(x: x + start, y: y + h))
                path.addLine(to: Point(x: x + start + h, y: y))
                path.addLine(to: Point(x: x + start + h + band, y: y))
                path.addLine(to: Point(x: x + start + band, y: y + h))
                path.closeSubpath()
                start += band * 2.4
            }
        case .sun:
            let radius = min(w, h) * 0.26
            path.addEllipse(in: Rect(x: x + w * 0.5 - radius, y: y + h * 0.42 - radius, width: radius * 2, height: radius * 2))
            for bar in 0..<4 {
                let top = y + h * (0.62 + Double(bar) * 0.07)
                path.addRect(Rect(x: x, y: top, width: w, height: h * (0.035 - Double(bar) * 0.005)))
            }
        case .grid:
            let step = w / 9
            for row in 0..<9 {
                for column in 0..<9 where (row * 7 + column * 3 + seed) % 4 == 0 {
                    path.addRect(Rect(x: x + Double(column) * step + step * 0.2, y: y + Double(row) * step + step * 0.2, width: step * 0.6, height: step * 0.6))
                }
            }
        case .waves:
            for wave in 0..<5 {
                let baseline = y + h * (0.2 + Double(wave) * 0.13)
                let amplitude = h * 0.05
                path.move(to: Point(x: x, y: baseline))
                var cursor = x
                let length = w / 3
                while cursor < x + w {
                    path.addCurve(
                        to: Point(x: cursor + length, y: baseline),
                        control1: Point(x: cursor + length * 0.35, y: baseline - amplitude),
                        control2: Point(x: cursor + length * 0.65, y: baseline + amplitude)
                    )
                    cursor += length
                }
            }
        case .dots:
            var generator = SeededGenerator(seed: UInt64(seed + 11))
            for _ in 0..<22 {
                let cx = x + Double(generator.next() % 1000) / 1000 * w
                let cy = y + Double(generator.next() % 1000) / 1000 * h * 0.7
                let radius = (0.015 + Double(generator.next() % 1000) / 1000 * 0.06) * w
                path.addEllipse(in: Rect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2))
            }
        }
        return path
    }
}

// MARK: - Icons

enum GlyphKind {
    case play, pause, next, previous, search, listen, friends, chevronDown, chevronUp, lyrics, lock, lockOpen
}

/// An icon, `size` points square, in the foreground style.
@View
struct Glyph {
    let kind: GlyphKind
    let size: Double

    var body: some View {
        Group {
            if kind.isStroked {
                GlyphShape(kind: kind).stroke(.foreground, style: StrokeStyle(lineWidth: max(1.5, size * 0.11), lineCap: .round, lineJoin: .round))
            } else {
                GlyphShape(kind: kind).fill(.foreground)
            }
        }
        .frame(width: size, height: size)
    }
}

extension GlyphKind {
    var isStroked: Bool {
        switch self {
        case .search, .chevronDown, .chevronUp, .lyrics, .lock, .lockOpen: true
        case .play, .pause, .next, .previous, .listen, .friends: false
        }
    }
}

@View
struct GlyphShape: Shape {
    let kind: GlyphKind

    func path(in rect: Rect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        func p(_ fx: Double, _ fy: Double) -> Point { Point(x: rect.minX + fx * w, y: rect.minY + fy * h) }
        switch kind {
        case .play:
            path.move(to: p(0.22, 0.1))
            path.addLine(to: p(0.9, 0.5))
            path.addLine(to: p(0.22, 0.9))
            path.closeSubpath()
        case .pause:
            path.addRoundedRect(Rect(origin: p(0.18, 0.1), size: Size(width: w * 0.22, height: h * 0.8)), radiusX: w * 0.05, radiusY: w * 0.05)
            path.addRoundedRect(Rect(origin: p(0.6, 0.1), size: Size(width: w * 0.22, height: h * 0.8)), radiusX: w * 0.05, radiusY: w * 0.05)
        case .next:
            path.move(to: p(0.08, 0.15))
            path.addLine(to: p(0.48, 0.5))
            path.addLine(to: p(0.08, 0.85))
            path.closeSubpath()
            path.move(to: p(0.46, 0.15))
            path.addLine(to: p(0.86, 0.5))
            path.addLine(to: p(0.46, 0.85))
            path.closeSubpath()
            path.addRect(Rect(origin: p(0.84, 0.15), size: Size(width: w * 0.1, height: h * 0.7)))
        case .previous:
            path.move(to: p(0.92, 0.15))
            path.addLine(to: p(0.52, 0.5))
            path.addLine(to: p(0.92, 0.85))
            path.closeSubpath()
            path.move(to: p(0.54, 0.15))
            path.addLine(to: p(0.14, 0.5))
            path.addLine(to: p(0.54, 0.85))
            path.closeSubpath()
            path.addRect(Rect(origin: p(0.06, 0.15), size: Size(width: w * 0.1, height: h * 0.7)))
        case .search:
            path.addEllipse(in: Rect(origin: p(0.1, 0.1), size: Size(width: w * 0.58, height: h * 0.58)))
            path.move(to: p(0.6, 0.6))
            path.addLine(to: p(0.9, 0.9))
        case .listen:
            for (index, height) in [0.4, 0.75, 1.0, 0.6, 0.85].enumerated() {
                let bar = w * 0.12
                let left = 0.06 + Double(index) * 0.19
                let top = 0.5 - height * 0.42
                path.addRoundedRect(
                    Rect(origin: p(left, top), size: Size(width: bar, height: h * height * 0.84)),
                    radiusX: bar / 2, radiusY: bar / 2
                )
            }
        case .friends:
            path.addEllipse(in: Rect(origin: p(0.1, 0.12), size: Size(width: w * 0.34, height: h * 0.34)))
            path.addEllipse(in: Rect(origin: p(0.0, 0.52), size: Size(width: w * 0.54, height: h * 0.5)))
            path.addEllipse(in: Rect(origin: p(0.56, 0.18), size: Size(width: w * 0.28, height: h * 0.28)))
            path.addEllipse(in: Rect(origin: p(0.48, 0.54), size: Size(width: w * 0.46, height: h * 0.42)))
        case .chevronDown:
            path.move(to: p(0.15, 0.35))
            path.addLine(to: p(0.5, 0.68))
            path.addLine(to: p(0.85, 0.35))
        case .chevronUp:
            path.move(to: p(0.15, 0.65))
            path.addLine(to: p(0.5, 0.32))
            path.addLine(to: p(0.85, 0.65))
        case .lyrics:
            path.addRoundedRect(Rect(origin: p(0.08, 0.12), size: Size(width: w * 0.84, height: h * 0.6)), radiusX: w * 0.14, radiusY: w * 0.14)
            path.move(to: p(0.3, 0.72))
            path.addLine(to: p(0.24, 0.92))
            path.addLine(to: p(0.48, 0.72))
            path.move(to: p(0.28, 0.36))
            path.addLine(to: p(0.72, 0.36))
            path.move(to: p(0.28, 0.5))
            path.addLine(to: p(0.58, 0.5))
        case .lock, .lockOpen:
            path.addRoundedRect(Rect(origin: p(0.18, 0.45), size: Size(width: w * 0.64, height: h * 0.47)), radiusX: w * 0.08, radiusY: w * 0.08)
            let lift = kind == .lockOpen ? 0.12 : 0
            path.move(to: p(0.32, 0.45 - lift))
            path.addLine(to: p(0.32, 0.3 - lift))
            path.addCurve(to: p(0.68, 0.3 - lift), control1: p(0.32, 0.04 - lift), control2: p(0.68, 0.04 - lift))
            if kind == .lock {
                path.addLine(to: p(0.68, 0.45))
            }
        }
        return path
    }
}
