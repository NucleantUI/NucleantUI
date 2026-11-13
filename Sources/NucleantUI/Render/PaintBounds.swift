//
//  PaintBounds.swift
//  NucleantUI
//
//  How big a command can paint. An automatic render node's image is the
//  bounds of what its view actually drew — not the view's frame, which a
//  glow, a shadow stroke or an `.offset` overrun freely — so every command
//  has to say, conservatively, where its pixels can land. Over-estimating
//  costs a few transparent pixels; under-estimating cuts the drawing.
//

extension Path {
    /// The box the elements lie in — control points included, which bounds
    /// the curve they control.
    var boundingBox: Rect? {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        func include(_ p: Point) {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        // One sweep over the points, the verbs saying which are positions:
        // a rect keeps its size and an ellipse its radii there too.
        var p = 0
        for verb in verbs {
            switch verb {
            case .move, .line:
                include(points[p])
                p += 1
            case .quad:
                include(points[p]); include(points[p + 1])
                p += 2
            case .cubic:
                include(points[p]); include(points[p + 1]); include(points[p + 2])
                p += 3
            case .close, .embedded:
                break
            case .rect:
                include(points[p]); include(points[p] + points[p + 1])
                p += 3
            case .ellipse:
                include(points[p] - points[p + 1]); include(points[p] + points[p + 1])
                p += 2
            }
        }
        for item in embedded {
            switch item {
            case .text(let string, let origin, let font):
                let extent = Path.textExtent(string, font: font)
                include(origin); include(Point(x: origin.x + extent.width, y: origin.y + extent.height))
            case .image(_, let rect):
                include(Point(x: rect.minX, y: rect.minY)); include(Point(x: rect.maxX, y: rect.maxY))
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension Rect {
    /// The smallest rect holding both.
    func union(_ other: Rect) -> Rect {
        let lo = origin.lanewiseMin(other.origin)
        let hi = (origin + size).lanewiseMax(other.origin + other.size)
        return Rect(origin: lo, size: hi - lo)
    }

    /// Grown by `amount` on every side.
    func expanded(by amount: Double) -> Rect {
        Rect(origin: origin - amount, size: size + 2 * amount)
    }

    /// Whether any area is shared — touching edges do not count.
    func intersects(_ other: Rect) -> Bool {
        all((origin .< other.origin + other.size) .& (other.origin .< origin + size))
    }

    /// The box around this rect's corners under `transform`.
    ///
    /// Without a rotation or a shear, x lands where x alone says and y where
    /// y does, so two opposite corners already hold every coordinate the
    /// other two would; otherwise all four are needed.
    func applying(_ transform: Transform) -> Rect {
        guard !transform.isIdentity else { return self }
        let a = transform.apply(to: origin)
        let d = transform.apply(to: origin + size)
        var lo = a.lanewiseMin(d)
        var hi = a.lanewiseMax(d)
        if transform.e12 != 0 || transform.e21 != 0 {
            let b = transform.apply(to: Point(x: maxX, y: minY))
            let c = transform.apply(to: Point(x: minX, y: maxY))
            lo = lo.lanewiseMin(b.lanewiseMin(c))
            hi = hi.lanewiseMax(b.lanewiseMax(c))
        }
        return Rect(origin: lo, size: hi - lo)
    }
}

extension DrawCommand {
    /// The box this command can put pixels in, in the list's coordinates
    /// before its state's transform and clip (`DrawState.paintBounds(of:)`
    /// takes it the rest of the way). `nil` when it paints nothing.
    var paintBox: Rect? {
        switch self {
        case .shape(let draw):
            // `Color.clear` is a shape with nothing visible — the renderer
            // skips it, and so does the image it would otherwise size.
            let fills = draw.fill.map { !$0.isClear } ?? false
            let strokes = (draw.stroke.map { !$0.isClear } ?? false) && draw.strokeStyle.lineWidth > 0
            guard fills || strokes else { return nil }
            // The path's own box, not just `bounds`: a custom `Shape` may
            // draw past the rect it was given. A stroke reaches half its
            // width outside the path, and a miter join up to the miter
            // limit (ThorVG's default is 4) times that.
            var rect = draw.pathBox.map { $0.union(draw.bounds) } ?? draw.bounds
            if strokes {
                let reach = draw.strokeStyle.lineWidth * (draw.strokeStyle.lineJoin == .miter ? 2 : 0.5)
                rect = rect.expanded(by: reach)
            }
            // A path in its own space, out to where that space lands.
            if let origin = draw.origin {
                rect.origin += origin
            }
            return rect
        case .text(let draw):
            // Glyphs overshoot the layout box a little — descenders, an
            // italic shear — so give them room in proportion to the size.
            return draw.frame.expanded(by: draw.font.size * 0.5)
        case .image(let draw):
            return draw.frame
        case .svg(let draw):
            return draw.frame
        case .canvas(let draw):
            return draw.frame
        }
    }
}

extension Rect {
    /// Whether `other` lies entirely inside.
    func contains(_ other: Rect) -> Bool {
        all((other.origin .>= origin) .& (other.origin + other.size .<= origin + size))
    }
}
