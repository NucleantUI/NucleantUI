//
//  Path+Building.swift
//  NucleantUI
//
//  The rest of SwiftUI's `Path` API on top of the elements `Path` is made of:
//  quadratic curves, arcs, appending paths and rects with a transform,
//  applying a transform to a whole path, and measuring one.
//
//  Angles follow SwiftUI's: the y axis points down, so an angle that grows
//  runs clockwise on screen, and `addArc`'s `clockwise: true` — decreasing
//  angles — is the one that reads as counterclockwise there.
//

import Foundation

/// A quarter ellipse as one cubic: the distance of its control points along
/// the tangents, as a fraction of the radius.
private let quarterArc = 0.5522847498307936

extension Path {

    // MARK: Creating

    public init(_ rect: Rect) {
        self.init()
        addRect(rect)
    }

    public init(roundedRect rect: Rect, cornerRadius: Double, style: RoundedCornerStyle = .circular) {
        self.init()
        addRoundedRect(in: rect, cornerSize: Size(width: cornerRadius, height: cornerRadius), style: style)
    }

    public init(roundedRect rect: Rect, cornerSize: Size, style: RoundedCornerStyle = .circular) {
        self.init()
        addRoundedRect(in: rect, cornerSize: cornerSize, style: style)
    }

    public init(ellipseIn rect: Rect) {
        self.init()
        addEllipse(in: rect)
    }

    // MARK: Inspecting

    /// Where the next segment starts from, or `nil` for an empty path. After
    /// a closed subpath, the point it started at.
    public var currentPoint: Point? {
        var current: Point?
        var start: Point?
        for element in elements {
            switch element {
            case .move(let p):
                current = p
                start = p
            case .line(let p), .quad(_, let p), .cubic(_, _, let p):
                current = p
            case .close:
                current = start
            case .rect(let rect, _, _):
                current = rect.origin
                start = rect.origin
            case .ellipse(let center, let rx, _):
                current = Point(x: center.x + rx, y: center.y)
                start = current
            case .text, .image:
                break
            }
        }
        return current
    }

    /// The smallest rect that holds the path's drawn extent — the curves
    /// themselves, not their control points. Zero for an empty path.
    public var boundingRect: Rect {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        func include(_ p: Point) {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        var current = Point.zero
        var start = Point.zero
        for element in elements {
            switch element {
            case .move(let p):
                include(p)
                current = p
                start = p
            case .line(let p):
                include(p)
                current = p
            case .quad(let control, let end):
                let from = current
                for step in 1...24 {
                    let t = Double(step) / 24
                    let u = 1 - t
                    include(Point(
                        x: u * u * from.x + 2 * u * t * control.x + t * t * end.x,
                        y: u * u * from.y + 2 * u * t * control.y + t * t * end.y
                    ))
                }
                current = end
            case .cubic(let c1, let c2, let end):
                let from = current
                for step in 1...24 {
                    let t = Double(step) / 24
                    let u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    include(Point(
                        x: a * from.x + b * c1.x + c * c2.x + d * end.x,
                        y: a * from.y + b * c1.y + c * c2.y + d * end.y
                    ))
                }
                current = end
            case .close:
                current = start
            case .rect(let rect, _, _):
                include(Point(x: rect.minX, y: rect.minY)); include(Point(x: rect.maxX, y: rect.maxY))
                current = rect.origin
                start = current
            case .ellipse(let center, let rx, let ry):
                include(Point(x: center.x - rx, y: center.y - ry)); include(Point(x: center.x + rx, y: center.y + ry))
                current = Point(x: center.x + rx, y: center.y)
                start = current
            case .text(let string, let origin, let font):
                let extent = Path.textExtent(string, font: font)
                include(origin); include(Point(x: origin.x + extent.width, y: origin.y + extent.height))
            case .image(_, let rect):
                include(Point(x: rect.minX, y: rect.minY)); include(Point(x: rect.maxX, y: rect.maxY))
            }
        }
        guard minX <= maxX, minY <= maxY else { return Rect(x: 0, y: 0, width: 0, height: 0) }
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Calls `body` with each element, in order.
    public func forEach(_ body: (Element) -> Void) {
        for element in elements { body(element) }
    }

    // MARK: Lines and curves

    public mutating func addQuadCurve(to end: Point, control: Point) {
        elements.append(.quad(control: control, end: end))
    }

    /// A polyline: a subpath moving to the first point and running a line to
    /// each of the rest.
    public mutating func addLines(_ points: [Point]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
    }

    // MARK: Rects and ellipses

    public mutating func addRect(_ rect: Rect, transform: Transform) {
        addPath(Path(rect), transform: transform)
    }

    public mutating func addRects(_ rects: [Rect], transform: Transform = .identity) {
        for rect in rects { addRect(rect, transform: transform) }
    }

    /// A rect with elliptical corners of `cornerSize` (each at most half the
    /// rect). `style` is accepted for source compatibility: the corner is
    /// always circular/elliptical.
    public mutating func addRoundedRect(
        in rect: Rect,
        cornerSize: Size,
        style: RoundedCornerStyle = .circular,
        transform: Transform = .identity
    ) {
        let rounded = Path { $0.addRoundedRect(rect, radiusX: cornerSize.width, radiusY: cornerSize.height) }
        addPath(rounded, transform: transform)
    }

    public mutating func addEllipse(in rect: Rect, transform: Transform) {
        addPath(Path(ellipseIn: rect), transform: transform)
    }

    // MARK: Arcs

    /// An arc of the circle about `center`, from `startAngle` to `endAngle`.
    /// A line joins the current point to the arc's start, or the path moves
    /// there if it has none.
    ///
    /// `clockwise: true` runs through decreasing angles — counterclockwise on
    /// screen, as in SwiftUI. Equal angles draw no arc.
    public mutating func addArc(
        center: Point,
        radius: Double,
        startAngle: Angle,
        endAngle: Angle,
        clockwise: Bool,
        transform: Transform = .identity
    ) {
        var sweep = (endAngle.radians - startAngle.radians).truncatingRemainder(dividingBy: 2 * .pi)
        if clockwise, sweep > 0 { sweep -= 2 * .pi }
        if !clockwise, sweep < 0 { sweep += 2 * .pi }
        // A full turn asked for with a whole-turn difference stays a turn.
        if sweep == 0, endAngle.radians != startAngle.radians {
            sweep = clockwise ? -2 * .pi : 2 * .pi
        }
        addRelativeArc(center: center, radius: radius, startAngle: startAngle, delta: Angle(radians: sweep), transform: transform)
    }

    /// An arc of the circle about `center`, from `startAngle` through
    /// `delta`: positive runs through increasing angles (clockwise on
    /// screen), negative through decreasing ones.
    public mutating func addRelativeArc(
        center: Point,
        radius: Double,
        startAngle: Angle,
        delta: Angle,
        transform: Transform = .identity
    ) {
        var arc = Path()
        let start = startAngle.radians
        let sweep = delta.radians
        let first = Point(x: center.x + radius * cos(start), y: center.y + radius * sin(start))
        if currentPoint != nil {
            arc.addLine(to: first)
        } else {
            arc.move(to: first)
        }
        let pieces = Swift.max(1, Int((abs(sweep) / (.pi / 2)).rounded(.up)))
        let step = sweep / Double(pieces)
        let k = 4.0 / 3.0 * tan(step / 4)
        var angle = start
        for _ in 0..<pieces {
            let next = angle + step
            let p0 = Point(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            let p3 = Point(x: center.x + radius * cos(next), y: center.y + radius * sin(next))
            let c1 = Point(x: p0.x - k * radius * sin(angle), y: p0.y + k * radius * cos(angle))
            let c2 = Point(x: p3.x + k * radius * sin(next), y: p3.y - k * radius * cos(next))
            arc.addCurve(to: p3, control1: c1, control2: c2)
            angle = next
        }
        addPath(arc, transform: transform)
    }

    /// The rounded corner at `tangent1End` of the path from the current
    /// point through it to `tangent2End`: a circle of `radius` tangent to
    /// both lines, with a line running to where it touches the first.
    public mutating func addArc(
        tangent1End: Point,
        tangent2End: Point,
        radius: Double,
        transform: Transform = .identity
    ) {
        guard let p0 = currentPoint else {
            move(to: tangent1End)
            return
        }
        let p1 = tangent1End, p2 = tangent2End
        func unit(_ from: Point, _ to: Point) -> Point? {
            let dx = to.x - from.x, dy = to.y - from.y
            let length = (dx * dx + dy * dy).squareRoot()
            return length > 0 ? Point(x: dx / length, y: dy / length) : nil
        }
        guard radius > 0, let v1 = unit(p1, p0), let v2 = unit(p1, p2) else {
            addLine(to: p1)
            return
        }
        let cross = v1.x * v2.y - v1.y * v2.x
        let dot = v1.x * v2.x + v1.y * v2.y
        // Straight on, or doubling back: no corner to round.
        guard abs(cross) > 1e-9 else {
            addLine(to: p1)
            return
        }
        let half = acos(Swift.max(-1, Swift.min(1, dot))) / 2
        let reach = radius / tan(half)
        let touch1 = Point(x: p1.x + v1.x * reach, y: p1.y + v1.y * reach)
        let touch2 = Point(x: p1.x + v2.x * reach, y: p1.y + v2.y * reach)
        guard let bisector = unit(Point.zero, Point(x: v1.x + v2.x, y: v1.y + v2.y)) else {
            addLine(to: p1)
            return
        }
        let toCenter = radius / sin(half)
        let center = Point(x: p1.x + bisector.x * toCenter, y: p1.y + bisector.y * toCenter)
        let a1 = atan2(touch1.y - center.y, touch1.x - center.x)
        let a2 = atan2(touch2.y - center.y, touch2.x - center.x)
        var delta = a2 - a1
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        addRelativeArc(center: center, radius: radius, startAngle: Angle(radians: a1), delta: Angle(radians: delta), transform: transform)
    }

    // MARK: Combining and transforming

    /// `path`'s elements appended after this one's, each mapped through
    /// `transform`.
    public mutating func addPath(_ path: Path, transform: Transform = .identity) {
        guard !transform.isIdentity else {
            elements.append(contentsOf: path.elements)
            return
        }
        elements.append(contentsOf: path.applying(transform).elements)
    }

    /// The path mapped through `transform`. A rect or ellipse that stays
    /// axis-aligned under it stays one; otherwise it becomes lines and
    /// curves.
    public func applying(_ transform: Transform) -> Path {
        guard !transform.isIdentity else { return self }
        let aligned = transform.e12 == 0 && transform.e21 == 0
        var result = Path()
        func map(_ p: Point) -> Point { transform.apply(to: p) }
        for element in elements {
            switch element {
            case .move(let p):
                result.elements.append(.move(map(p)))
            case .line(let p):
                result.elements.append(.line(map(p)))
            case .quad(let control, let end):
                result.elements.append(.quad(control: map(control), end: map(end)))
            case .cubic(let c1, let c2, let end):
                result.elements.append(.cubic(control1: map(c1), control2: map(c2), end: map(end)))
            case .close:
                result.elements.append(.close)
            case .rect(let rect, let rx, let ry):
                if aligned {
                    let a = map(Point(x: rect.minX, y: rect.minY))
                    let b = map(Point(x: rect.maxX, y: rect.maxY))
                    result.elements.append(.rect(
                        Rect(x: Swift.min(a.x, b.x), y: Swift.min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)),
                        radiusX: rx * abs(transform.e11), radiusY: ry * abs(transform.e22)
                    ))
                } else {
                    for primitive in Path.primitives(rect: rect, radiusX: rx, radiusY: ry) {
                        result.elements.append(primitive.mapped(map))
                    }
                }
            case .ellipse(let center, let rx, let ry):
                if aligned {
                    result.elements.append(.ellipse(
                        center: map(center),
                        radiusX: rx * abs(transform.e11), radiusY: ry * abs(transform.e22)
                    ))
                } else {
                    for primitive in Path.primitives(ellipseAt: center, radiusX: rx, radiusY: ry) {
                        result.elements.append(primitive.mapped(map))
                    }
                }
            case .text(let string, let origin, let font):
                // Text stays upright: its anchor moves, and its size follows the scale.
                result.elements.append(.text(string, origin: map(origin), font: font.size(font.size * abs(transform.e22))))
            case .image(let image, let rect):
                // An image stays axis-aligned: the box around the mapped rect.
                result.elements.append(.image(image, in: rect.applying(transform)))
            }
        }
        return result
    }

    // MARK: Text

    /// A generous box for `string` in `font` — never smaller than the real
    /// one, so bounds built from it cut nothing. (Measuring it exactly needs
    /// the main actor and the font engine.)
    static func textExtent(_ string: String, font: Font) -> Size {
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let longest = lines.map(\.count).max() ?? 0
        return Size(width: Double(longest) * font.size, height: Double(lines.count) * font.size * 1.5)
    }

    // MARK: Rects and ellipses as lines and curves

    private static func primitives(rect: Rect, radiusX: Double, radiusY: Double) -> [Element] {
        let rx = Swift.min(Swift.max(radiusX, 0), rect.width / 2)
        let ry = Swift.min(Swift.max(radiusY, 0), rect.height / 2)
        let (l, t, r, b) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        guard rx > 0, ry > 0 else {
            return [
                .move(Point(x: l, y: t)), .line(Point(x: r, y: t)),
                .line(Point(x: r, y: b)), .line(Point(x: l, y: b)), .close,
            ]
        }
        let kx = rx * quarterArc, ky = ry * quarterArc
        return [
            .move(Point(x: l + rx, y: t)),
            .line(Point(x: r - rx, y: t)),
            .cubic(control1: Point(x: r - rx + kx, y: t), control2: Point(x: r, y: t + ry - ky), end: Point(x: r, y: t + ry)),
            .line(Point(x: r, y: b - ry)),
            .cubic(control1: Point(x: r, y: b - ry + ky), control2: Point(x: r - rx + kx, y: b), end: Point(x: r - rx, y: b)),
            .line(Point(x: l + rx, y: b)),
            .cubic(control1: Point(x: l + rx - kx, y: b), control2: Point(x: l, y: b - ry + ky), end: Point(x: l, y: b - ry)),
            .line(Point(x: l, y: t + ry)),
            .cubic(control1: Point(x: l, y: t + ry - ky), control2: Point(x: l + rx - kx, y: t), end: Point(x: l + rx, y: t)),
            .close,
        ]
    }

    private static func primitives(ellipseAt c: Point, radiusX rx: Double, radiusY ry: Double) -> [Element] {
        let kx = rx * quarterArc, ky = ry * quarterArc
        return [
            .move(Point(x: c.x + rx, y: c.y)),
            .cubic(control1: Point(x: c.x + rx, y: c.y + ky), control2: Point(x: c.x + kx, y: c.y + ry), end: Point(x: c.x, y: c.y + ry)),
            .cubic(control1: Point(x: c.x - kx, y: c.y + ry), control2: Point(x: c.x - rx, y: c.y + ky), end: Point(x: c.x - rx, y: c.y)),
            .cubic(control1: Point(x: c.x - rx, y: c.y - ky), control2: Point(x: c.x - kx, y: c.y - ry), end: Point(x: c.x, y: c.y - ry)),
            .cubic(control1: Point(x: c.x + kx, y: c.y - ry), control2: Point(x: c.x + rx, y: c.y - ky), end: Point(x: c.x + rx, y: c.y)),
            .close,
        ]
    }
}

extension Path.Element {
    /// The element with every point passed through `map`. Only the
    /// line-and-curve elements — rects and ellipses are expanded first.
    fileprivate func mapped(_ map: (Point) -> Point) -> Path.Element {
        switch self {
        case .move(let p): return .move(map(p))
        case .line(let p): return .line(map(p))
        case .quad(let control, let end): return .quad(control: map(control), end: map(end))
        case .cubic(let c1, let c2, let end): return .cubic(control1: map(c1), control2: map(c2), end: map(end))
        case .close, .rect, .ellipse, .text, .image: return self
        }
    }
}
