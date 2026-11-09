//
//  Poster.swift
//  Atlas
//
//  A destination's poster, drawn rather than photographed: a sky in its
//  palette, a sun, and a horizon for its landscape — peaks, a coast, dunes,
//  a skyline or a treeline. Every shape is in unit space and scaled to the
//  poster, so the same poster draws as a card in the gallery and as the
//  header of the destination's own page.
//

import NucleantUI

@View
struct Poster {
    let destination: Destination

    var body: some View {
        let palette = destination.palette
        ZStack {
            Rectangle().fill(.linearGradient(colors: [palette.skyTop, palette.skyBottom]))
            Sun().fill(palette.sun)
            Horizon(landscape: destination.landscape, layer: 0)
                .fill(palette.land.opacity(0.55))
            Horizon(landscape: destination.landscape, layer: 1)
                .fill(palette.land)
        }
    }
}

/// The sun, up and to the right, sized by the poster's shorter side.
@View
struct Sun: Shape {
    func path(in rect: Rect) -> Path {
        let radius = min(rect.width, rect.height) * 0.12
        var path = Path()
        path.addEllipse(in: Rect(
            x: rect.minX + rect.width * 0.72 - radius,
            y: rect.minY + rect.height * 0.3 - radius,
            width: radius * 2,
            height: radius * 2
        ))
        return path
    }
}

/// The land along the bottom of a poster: two layers, the far one paler.
@View
struct Horizon: Shape {
    let landscape: Landscape
    /// 0 for the far layer, 1 for the near one.
    let layer: Int

    func path(in rect: Rect) -> Path {
        // Points in unit space: x across, y down from the top.
        let points: [(Double, Double)]
        switch (landscape, layer) {
        case (.mountains, 0):
            points = [(0, 0.62), (0.18, 0.38), (0.32, 0.55), (0.5, 0.3), (0.68, 0.52), (0.84, 0.36), (1, 0.58)]
        case (.mountains, _):
            points = [(0, 0.78), (0.22, 0.52), (0.4, 0.72), (0.6, 0.48), (0.8, 0.7), (1, 0.6)]
        case (.coast, 0):
            points = [(0, 0.6), (0.25, 0.5), (0.45, 0.62), (0.62, 0.66), (1, 0.66)]
        case (.coast, _):
            points = [(0, 0.76), (0.3, 0.74), (0.55, 0.8), (0.8, 0.78), (1, 0.82)]
        case (.desert, 0):
            points = [(0, 0.66), (0.3, 0.54), (0.55, 0.64), (0.8, 0.5), (1, 0.6)]
        case (.desert, _):
            points = [(0, 0.82), (0.25, 0.66), (0.5, 0.8), (0.75, 0.7), (1, 0.84)]
        case (.city, 0):
            points = [(0, 0.66), (0.08, 0.66), (0.08, 0.5), (0.16, 0.5), (0.16, 0.58), (0.26, 0.58), (0.26, 0.42),
                      (0.32, 0.42), (0.32, 0.6), (0.46, 0.6), (0.46, 0.46), (0.56, 0.46), (0.56, 0.64), (0.7, 0.64),
                      (0.7, 0.4), (0.76, 0.36), (0.82, 0.4), (0.82, 0.6), (1, 0.6)]
        case (.city, _):
            points = [(0, 0.8), (0.12, 0.8), (0.12, 0.66), (0.22, 0.62), (0.32, 0.66), (0.32, 0.78), (0.5, 0.78),
                      (0.5, 0.7), (0.62, 0.7), (0.62, 0.82), (0.78, 0.82), (0.78, 0.68), (0.9, 0.68), (0.9, 0.8), (1, 0.8)]
        case (.forest, 0):
            points = stride(from: 0.0, through: 1.0, by: 0.0625).map { x in
                (x, Int(x * 16) % 2 == 0 ? 0.62 : 0.5)
            }
        case (.forest, _):
            points = stride(from: 0.0, through: 1.0, by: 0.05).map { x in
                (x, Int(x * 20) % 2 == 0 ? 0.82 : 0.66)
            }
        }
        var path = Path()
        path.move(to: Point(x: rect.minX, y: rect.maxY))
        for (x, y) in points {
            path.addLine(to: Point(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height))
        }
        path.addLine(to: Point(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
