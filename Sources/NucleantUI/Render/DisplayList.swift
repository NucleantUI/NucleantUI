//
//  DisplayList.swift
//  NucleantUI
//
//  The flat, absolute-coordinate output of one layout pass. Everything above
//  this line is view/layout code that never names a renderer; everything
//  below it (`SkiaDisplayRenderer`) only ever sees this.
//

/// A resolved path in absolute window coordinates.
///
/// Kept the way path libraries keep one: a byte per element saying what it
/// is, and the points of every element in one array — a line takes its
/// byte and one point, not the room of the largest element. Texts and
/// images, which the renderer draws after the geometry, are a short list of
/// their own.
public struct Path: Hashable, Sendable {
    public enum Element: Hashable, Sendable {
        case move(Point)
        case line(Point)
        case quad(control: Point, end: Point)
        case cubic(control1: Point, control2: Point, end: Point)
        case close
        /// A rect with per-axis corner radii — `append_rect` handles this in
        /// one call, and doing it here keeps ThorVG's own rounding maths.
        case rect(Rect, radiusX: Double, radiusY: Double)
        case ellipse(center: Point, radiusX: Double, radiusY: Double)
        /// Text with its top-left at `origin`, a line per `\n`. Painted with
        /// the path's fill, as an image is; stroking leaves both out.
        case text(String, origin: Point, font: Font)
        /// An image stretched into `rect`, faded by the fill's alpha.
        case image(RasterImage, in: Rect)
    }

    /// What an element is.
    enum Verb: UInt8, Hashable, Sendable {
        case move, line, quad, cubic, close, rect, ellipse
        /// A text or an image: the next of `embedded`.
        case embedded
    }

    /// A text or an image in the path.
    enum Embedded: Hashable, Sendable {
        case text(String, origin: Point, font: Font)
        case image(RasterImage, in: Rect)
    }

    /// What each element is, in order.
    private(set) var verbs: [Verb] = []
    /// The elements' points, in order: a move's or a line's one; a quad's
    /// control and end; a cubic's two controls and end; a rect's origin,
    /// size and corner radii; an ellipse's center and radii.
    private(set) var points: [Point] = []
    /// The texts and images, in order.
    private(set) var embedded: [Embedded] = []

    public init() {}

    public init(_ build: (inout Path) -> Void) {
        build(&self)
    }

    public var isEmpty: Bool { verbs.isEmpty }

    /// The elements, in order — made from what the path keeps, on each ask.
    /// Code that only walks them reads `elementSequence`, which makes no
    /// array.
    public var elements: [Element] {
        get {
            var result: [Element] = []
            result.reserveCapacity(verbs.count)
            for element in elementSequence { result.append(element) }
            return result
        }
        set {
            verbs.removeAll(keepingCapacity: true)
            points.removeAll(keepingCapacity: true)
            embedded.removeAll(keepingCapacity: true)
            for element in newValue { append(element) }
        }
    }

    /// The elements one at a time, read from what the path keeps as they
    /// are asked for.
    var elementSequence: ElementSequence { ElementSequence(path: self) }

    /// The only element, for a path of one — a rect or an ellipse the
    /// renderer draws in one call.
    var soleElement: Element? {
        guard verbs.count == 1 else { return nil }
        var sequence = elementSequence
        return sequence.next()
    }

    struct ElementSequence: Sequence, IteratorProtocol {
        private let path: Path
        private var verb = 0
        private var point = 0
        private var item = 0

        fileprivate init(path: Path) {
            self.path = path
        }

        mutating func next() -> Element? {
            guard verb < path.verbs.count else { return nil }
            let kind = path.verbs[verb]
            let p = point
            verb += 1
            switch kind {
            case .move:
                point += 1
                return .move(path.points[p])
            case .line:
                point += 1
                return .line(path.points[p])
            case .quad:
                point += 2
                return .quad(control: path.points[p], end: path.points[p + 1])
            case .cubic:
                point += 3
                return .cubic(control1: path.points[p], control2: path.points[p + 1], end: path.points[p + 2])
            case .close:
                return .close
            case .rect:
                point += 3
                let radii = path.points[p + 2]
                return .rect(Rect(origin: path.points[p], size: path.points[p + 1]), radiusX: radii.x, radiusY: radii.y)
            case .ellipse:
                point += 2
                let radii = path.points[p + 1]
                return .ellipse(center: path.points[p], radiusX: radii.x, radiusY: radii.y)
            case .embedded:
                item += 1
                switch path.embedded[item - 1] {
                case .text(let string, let origin, let font):
                    return .text(string, origin: origin, font: font)
                case .image(let image, let rect):
                    return .image(image, in: rect)
                }
            }
        }
    }

    /// `element`, after the rest.
    mutating func append(_ element: Element) {
        switch element {
        case .move(let point):
            move(to: point)
        case .line(let point):
            addLine(to: point)
        case .quad(let control, let end):
            verbs.append(.quad)
            points.append(control)
            points.append(end)
        case .cubic(let control1, let control2, let end):
            addCurve(to: end, control1: control1, control2: control2)
        case .close:
            closeSubpath()
        case .rect(let rect, let radiusX, let radiusY):
            addRoundedRect(rect, radiusX: radiusX, radiusY: radiusY)
        case .ellipse(let center, let radiusX, let radiusY):
            verbs.append(.ellipse)
            points.append(center)
            points.append(Point(x: radiusX, y: radiusY))
        case .text(let string, let origin, let font):
            addText(string, at: origin, font: font)
        case .image(let image, let rect):
            addImage(image, in: rect)
        }
    }

    /// `other`'s elements, after this path's.
    mutating func append(contentsOf other: Path) {
        verbs.append(contentsOf: other.verbs)
        points.append(contentsOf: other.points)
        embedded.append(contentsOf: other.embedded)
    }

    public mutating func move(to point: Point) {
        verbs.append(.move)
        points.append(point)
    }

    public mutating func addLine(to point: Point) {
        verbs.append(.line)
        points.append(point)
    }

    public mutating func addCurve(to end: Point, control1: Point, control2: Point) {
        verbs.append(.cubic)
        points.append(control1)
        points.append(control2)
        points.append(end)
    }

    public mutating func closeSubpath() {
        verbs.append(.close)
    }

    public mutating func addRect(_ rect: Rect, cornerRadius: Double = 0) {
        addRoundedRect(rect, radiusX: cornerRadius, radiusY: cornerRadius)
    }

    public mutating func addRoundedRect(_ rect: Rect, radiusX: Double, radiusY: Double) {
        verbs.append(.rect)
        points.append(rect.origin)
        points.append(rect.size)
        points.append(Point(x: radiusX, y: radiusY))
    }

    public mutating func addText(_ string: String, at origin: Point, font: Font) {
        verbs.append(.embedded)
        embedded.append(.text(string, origin: origin, font: font))
    }

    public mutating func addImage(_ image: RasterImage, in rect: Rect) {
        verbs.append(.embedded)
        embedded.append(.image(image, in: rect))
    }

    public mutating func addEllipse(in rect: Rect) {
        append(.ellipse(
            center: rect.center,
            radiusX: rect.width / 2,
            radiusY: rect.height / 2
        ))
    }

    /// Every element shifted — how a shape built in a view's local space
    /// becomes absolute. The points that are positions move; a rect's size
    /// and the radii stay.
    public func offsetBy(dx: Double, dy: Double) -> Path {
        guard dx != 0 || dy != 0 else { return self }
        let shift = Point(x: dx, y: dy)
        var copy = self
        var p = 0
        for verb in verbs {
            switch verb {
            case .move, .line:
                copy.points[p] += shift
                p += 1
            case .quad:
                copy.points[p] += shift
                copy.points[p + 1] += shift
                p += 2
            case .cubic:
                copy.points[p] += shift
                copy.points[p + 1] += shift
                copy.points[p + 2] += shift
                p += 3
            case .close, .embedded:
                break
            case .rect:
                copy.points[p] += shift
                p += 3
            case .ellipse:
                copy.points[p] += shift
                p += 2
            }
        }
        if !embedded.isEmpty {
            copy.embedded = embedded.map { item in
                switch item {
                case .text(let string, let origin, let font):
                    return .text(string, origin: origin + shift, font: font)
                case .image(let image, let rect):
                    return .image(image, in: rect.offsetBy(dx: dx, dy: dy))
                }
            }
        }
        return copy
    }
}

/// A clip that turned with the view it cuts: `rect`, rounded by
/// `cornerRadius`, under `transform` — `.clipped()` inside a
/// `.rotationEffect`.
public struct TransformedClip: Equatable, Sendable {
    public var rect: Rect
    public var cornerRadius: Double
    public var transform: Transform

    public init(rect: Rect, cornerRadius: Double = 0, transform: Transform) {
        self.rect = rect
        self.cornerRadius = cornerRadius
        self.transform = transform
    }
}

/// The clip and transform a command is drawn under — what the commands a
/// container places all share. A list keeps one for each run of commands
/// under the same state, and each command says which one it is drawn under.
public struct DrawState: Equatable, Sendable {
    public var transform: Transform
    public var clip: Rect?
    public var clipCornerRadius: Double
    /// Clips turned with the view they cut, on top of `clip`.
    public var transformedClips: [TransformedClip]

    public init(
        transform: Transform = .identity,
        clip: Rect? = nil,
        clipCornerRadius: Double = 0,
        transformedClips: [TransformedClip] = []
    ) {
        self.transform = transform
        self.clip = clip
        self.clipCornerRadius = clipCornerRadius
        self.transformedClips = transformedClips
    }

    /// Where a command whose own box is `box` can put pixels, in the list's
    /// coordinates: the box under the transform, inside the clip. `nil`
    /// when that is nothing.
    func paintBounds(of box: Rect) -> Rect? {
        // Anti-aliasing touches the pixel outside the edge.
        var result = box.applying(transform).expanded(by: 1)
        if let clip {
            result = result.intersection(clip)
        }
        guard result.width > 0, result.height > 0 else { return nil }
        return result
    }

    /// The state for the same commands drawn `(dx, dy)` further along. A
    /// transform is moved *after* it — a rotated card must not be re-rotated
    /// about the old anchor — which is the conjugated transform.
    func translated(dx: Double, dy: Double) -> DrawState {
        func moved(_ transform: Transform) -> Transform {
            guard !transform.isIdentity else { return transform }
            return Transform.translation(x: dx, y: dy)
                .concatenating(transform)
                .concatenating(Transform.translation(x: -dx, y: -dy))
        }
        var copy = self
        copy.transform = moved(transform)
        copy.clip = clip?.offsetBy(dx: dx, dy: dy)
        if !transformedClips.isEmpty {
            copy.transformedClips = transformedClips.map {
                TransformedClip(rect: $0.rect.offsetBy(dx: dx, dy: dy), cornerRadius: $0.cornerRadius, transform: moved($0.transform))
            }
        }
        return copy
    }

    /// This state with `transform` — a move and a scale, no flip — applied
    /// after its own. The geometry of the commands stays as it is; their
    /// transform, and the clips on screen, take it on.
    func transformed(by transform: Transform) -> DrawState {
        let radiusScale = min(transform.e11, transform.e22)
        var copy = self
        copy.transform = transform.concatenating(self.transform)
        copy.clip = clip?.applying(transform)
        copy.clipCornerRadius *= radiusScale
        if !transformedClips.isEmpty {
            copy.transformedClips = transformedClips.map {
                TransformedClip(rect: $0.rect, cornerRadius: $0.cornerRadius, transform: transform.concatenating($0.transform))
            }
        }
        return copy
    }

    /// The same state cut to `rect` as well as to its own clip. A rounded
    /// clip that holds `rect` entirely is replaced by it — the rounding lies
    /// outside; one that does not is the caller's problem to avoid
    /// (`roundedClipCrosses(_:)`).
    func clipped(to rect: Rect) -> DrawState {
        var copy = self
        if let clip, !(clipCornerRadius > 0 && clip.insetBy(clipCornerRadius).contains(rect)) {
            copy.clip = clip.intersection(rect)
        } else {
            copy.clip = rect
            copy.clipCornerRadius = 0
        }
        return copy
    }

    /// Whether a rounded clip's rounding reaches into `rect`, where a cut
    /// to `rect` could not draw it.
    func roundedClipCrosses(_ rect: Rect) -> Bool {
        guard clipCornerRadius > 0, let clip else { return false }
        return !clip.insetBy(clipCornerRadius).contains(rect)
    }
}

/// One paint operation. `bounds` is the shape's own rect — gradients resolve
/// their `UnitPoint`s against it, so it travels with the command rather than
/// being recomputed from the path.
///
/// With `origin` set, `path` and `bounds` are in the shape's own space and
/// `origin` is where that space's corner lands in the list — under the
/// state's transform, as everything else in the command is. A shape view's
/// path is made that way, so it depends on the shape and its size alone;
/// without `origin`, the path is in the list's coordinates.
public struct ShapeDraw: Equatable, Sendable {
    public var path: Path {
        didSet { pathBox = path.boundingBox }
    }
    /// `path.boundingBox`, worked out with the path: the box is a walk over
    /// every element — a measure of every text in it — and a path drawn
    /// again keeps it.
    private(set) var pathBox: Rect?
    public var bounds: Rect
    public var fill: _ResolvedPaint?
    public var stroke: _ResolvedPaint?
    public var strokeStyle: StrokeStyle
    /// Where the path's own space starts in the list, for a path made in
    /// it; `nil` for a path in the list's coordinates.
    public var origin: Point?

    public init(
        path: Path,
        bounds: Rect,
        fill: _ResolvedPaint? = nil,
        stroke: _ResolvedPaint? = nil,
        strokeStyle: StrokeStyle = StrokeStyle(),
        origin: Point? = nil
    ) {
        self.init(
            path: path, pathBox: path.boundingBox, bounds: bounds, fill: fill, stroke: stroke,
            strokeStyle: strokeStyle, origin: origin
        )
    }

    /// The same, with the path's box already worked out — kept with a path
    /// that is drawn again.
    init(
        path: Path,
        pathBox: Rect?,
        bounds: Rect,
        fill: _ResolvedPaint?,
        stroke: _ResolvedPaint?,
        strokeStyle: StrokeStyle,
        origin: Point?
    ) {
        self.path = path
        self.pathBox = pathBox
        self.bounds = bounds
        self.fill = fill
        self.stroke = stroke
        self.strokeStyle = strokeStyle
        self.origin = origin
    }
}

public struct TextDraw: Equatable, Sendable {
    /// The text's lines, as layout broke them — or, for a draw made from a
    /// string, its lines at each "\n". Carried as they are, so a text laid
    /// out once is neither joined nor split again to be drawn.
    public var lines: [String]

    /// The text, its lines joined with "\n".
    public var string: String {
        get { lines.joined(separator: "\n") }
        set { lines = newValue.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
    }
    /// The box the text is laid out in — absolute, already sized by layout.
    public var frame: Rect
    public var font: Font
    public var color: Color
    public var alignment: TextAlignment
    public var lineLimit: Int?
    /// True when the string is wider than the box it was given, so the
    /// renderer should truncate with an ellipsis. Decided at layout time,
    /// where the natural width is already known — asking the renderer to work
    /// it out would mean measuring the same string twice.
    public var isTruncated: Bool
    /// False when the whole string fits the box on one line, so the renderer
    /// must not wrap it: ThorVG's own layout can find a label a fraction
    /// wider than the summed advances did, and would break a fitted single
    /// line in two.
    public var wraps: Bool
    /// Points after every character, as layout measured them: kerning or
    /// tracking.
    public var letterSpacing: Double
    /// Points added to `letterSpacing` on the last line only: below 0 when
    /// layout tightened that line to fit.
    public var lastLineTightening: Double
    /// Points between the bottom of one line and the top of the next.
    public var lineSpacing: Double
    /// A line along each line's baseline; `nil` for none. Its color, when
    /// `nil`, is `color`.
    public var underline: Text.LineStyle?
    /// A line through each line's middle; `nil` for none.
    public var strikethrough: Text.LineStyle?

    public init(
        string: String,
        frame: Rect,
        font: Font,
        color: Color,
        alignment: TextAlignment = .leading,
        lineLimit: Int? = nil,
        isTruncated: Bool = false,
        wraps: Bool = true,
        letterSpacing: Double = 0,
        lastLineTightening: Double = 0,
        lineSpacing: Double = 0,
        underline: Text.LineStyle? = nil,
        strikethrough: Text.LineStyle? = nil
    ) {
        self.init(
            lines: string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
            frame: frame,
            font: font,
            color: color,
            alignment: alignment,
            lineLimit: lineLimit,
            isTruncated: isTruncated,
            wraps: wraps,
            letterSpacing: letterSpacing,
            lastLineTightening: lastLineTightening,
            lineSpacing: lineSpacing,
            underline: underline,
            strikethrough: strikethrough
        )
    }

    /// A draw of lines already broken.
    init(
        lines: [String],
        frame: Rect,
        font: Font,
        color: Color,
        alignment: TextAlignment = .leading,
        lineLimit: Int? = nil,
        isTruncated: Bool = false,
        wraps: Bool = true,
        letterSpacing: Double = 0,
        lastLineTightening: Double = 0,
        lineSpacing: Double = 0,
        underline: Text.LineStyle? = nil,
        strikethrough: Text.LineStyle? = nil
    ) {
        self.lines = lines
        self.frame = frame
        self.font = font
        self.color = color
        self.alignment = alignment
        self.lineLimit = lineLimit
        self.isTruncated = isTruncated
        self.wraps = wraps
        self.letterSpacing = letterSpacing
        self.lastLineTightening = lastLineTightening
        self.lineSpacing = lineSpacing
        self.underline = underline
        self.strikethrough = strikethrough
    }
}

/// A bitmap stretched into `frame`.
public struct ImageDraw: Equatable, Sendable {
    public var image: RasterImage
    public var frame: Rect
    /// The inherited opacity — a bitmap has no colours to fade at layout
    /// time, so it carries the factor for the renderer to apply.
    public var opacity: Double

    public init(image: RasterImage, frame: Rect, opacity: Double = 1) {
        self.image = image
        self.frame = frame
        self.opacity = opacity
    }
}

/// An SVG document drawn into `frame`, as large as fits in proportion,
/// centered.
public struct SvgDraw: Equatable, Sendable {
    public var image: SvgImage
    public var frame: Rect
    /// A template's paint: everything the document draws painted in it, by
    /// the document's own coverage. `nil` draws the document's colors.
    public var tint: _ResolvedPaint?
    /// The inherited opacity, applied to the drawing as a whole — the
    /// document's colors are its own, not resolved at layout time.
    public var opacity: Double

    public init(image: SvgImage, frame: Rect, tint: _ResolvedPaint? = nil, opacity: Double = 1) {
        self.image = image
        self.frame = frame
        self.tint = tint
        self.opacity = opacity
    }
}

/// What a `Canvas` view draws with: handed the raw pointer of the node's
/// `SkCanvas`, already at the canvas's origin, inside its clip. A pointer
/// rather than the Skia type so the display list names no backend; builds
/// without Skia never run it.
struct CanvasDrawing: @unchecked Sendable {
    let run: @MainActor (OpaquePointer) -> Void
}

/// A `Canvas` view's place in the list: the renderer draws straight into the
/// node's own Skia canvas, at this point in paint order, instead of through
/// commands.
///
/// Compared by `generation` — bumped each time the view is rebuilt, which is
/// what a change to anything its renderer read does — and the geometry, so
/// an unchanged canvas leaves the node's list equal and it is not redrawn.
public struct CanvasDraw: Equatable, Sendable {
    public var frame: Rect
    /// The inherited opacity, applied to the canvas as a whole.
    public var opacity: Double
    let generation: Int
    let drawing: CanvasDrawing

    init(frame: Rect, opacity: Double = 1, generation: Int, drawing: CanvasDrawing) {
        self.frame = frame
        self.opacity = opacity
        self.generation = generation
        self.drawing = drawing
    }

    public static func == (lhs: CanvasDraw, rhs: CanvasDraw) -> Bool {
        lhs.generation == rhs.generation
            && lhs.frame == rhs.frame
            && lhs.opacity == rhs.opacity
    }
}

/// What is drawn. Where, under which clip and transform, is the list's to
/// say: `DisplayList.state(at:)`.
public enum DrawCommand: Equatable, Sendable {
    case shape(ShapeDraw)
    case text(TextDraw)
    case image(ImageDraw)
    case svg(SvgDraw)
    case canvas(CanvasDraw)
}

extension DrawCommand {
    /// The same command drawn `(dx, dy)` further along: its geometry moved.
    /// The state it is drawn under moves with the list
    /// (`DrawState.translated(dx:dy:)`).
    func translated(dx: Double, dy: Double) -> DrawCommand {
        guard dx != 0 || dy != 0 else { return self }
        switch self {
        case .shape(var draw):
            // A path in its own space moves with its origin, and is left as
            // it is — the same path, wherever it lands.
            if let origin = draw.origin {
                draw.origin = origin + Point(x: dx, y: dy)
            } else {
                draw.path = draw.path.offsetBy(dx: dx, dy: dy)
                draw.bounds = draw.bounds.offsetBy(dx: dx, dy: dy)
            }
            return .shape(draw)
        case .text(var draw):
            draw.frame = draw.frame.offsetBy(dx: dx, dy: dy)
            return .text(draw)
        case .image(var draw):
            draw.frame = draw.frame.offsetBy(dx: dx, dy: dy)
            return .image(draw)
        case .svg(var draw):
            draw.frame = draw.frame.offsetBy(dx: dx, dy: dy)
            return .svg(draw)
        case .canvas(var draw):
            draw.frame = draw.frame.offsetBy(dx: dx, dy: dy)
            return .canvas(draw)
        }
    }
}

/// The commands produced by one layout pass, in paint order, each under one
/// of the list's states.
///
/// `Equatable` so a `.shader` layer can tell whether the view under it drew
/// anything different since its canvas was last rasterized — comparing two
/// lists is far cheaper than a render that comes out identical.
public struct DisplayList: Equatable, Sendable {
    /// What is drawn, in paint order.
    public private(set) var commands: [DrawCommand] = []
    /// The clips and transforms the commands are drawn under, one for each
    /// run of commands that shares one: a new one starts at a command whose
    /// state differs from the one before it. The same commands under the
    /// same states make the same list, however it was put together.
    public private(set) var states: [DrawState] = []
    /// For each command, the index in `states` of the one it is drawn under.
    private(set) var stateIndices: [Int32] = []
    /// For each command, where it can put pixels, in the list's coordinates
    /// — after its transform, inside its clip; `nil` when it paints nothing.
    /// Worked out once, as the command is appended: culling, cutting a
    /// boundary into runs and damage all ask it, every pass. Not part of
    /// what the list is: it follows from the rest.
    private var bounds: [Rect?] = []
    /// Which kept list this is, and how far it was moved since: two lists
    /// with the same version are the same list, told without comparing a
    /// command. Given to what a pure subtree keeps (`PlacementCache.swift`),
    /// carried by a list that is that one as it is or moved once — a
    /// boundary holding one kept subtree, in its image's space — and
    /// dropped by anything else that changes it. Without one, lists are
    /// compared command by command.
    private(set) var version: Version?

    struct Version: Equatable, Sendable {
        let kept: Int
        var dx = 0.0
        var dy = 0.0
    }

    public init() {}

    public var isEmpty: Bool { commands.isEmpty }

    /// Number this list as the kept list `kept`.
    mutating func markKept(_ kept: Int) {
        version = Version(kept: kept)
    }

    /// The state `commands[index]` is drawn under.
    public func state(at index: Int) -> DrawState {
        states[Int(stateIndices[index])]
    }

    /// The index in `states` of the one `commands[index]` is drawn under.
    func stateIndex(at index: Int) -> Int {
        Int(stateIndices[index])
    }

    /// Where `commands[index]` can put pixels, in the list's coordinates —
    /// after its transform, inside its clip. `nil` when it paints nothing.
    func paintBounds(at index: Int) -> Rect? {
        bounds[index]
    }

    /// The commands in `range` as a list of their own, under their states
    /// and with their bounds: what appending them again appends. A run's
    /// states are numbered in order, so the range's are one stretch of
    /// `states`.
    func slice(_ range: Range<Int>) -> DisplayList {
        var copy = DisplayList()
        guard !range.isEmpty else { return copy }
        let first = stateIndices[range.lowerBound]
        let last = stateIndices[range.upperBound - 1]
        copy.states = Array(states[Int(first)...Int(last)])
        copy.stateIndices = stateIndices[range].map { $0 - first }
        copy.commands = Array(commands[range])
        copy.bounds = Array(bounds[range])
        return copy
    }

    public mutating func append(_ command: DrawCommand, under state: DrawState = DrawState()) {
        append(command, under: state, bounds: command.paintBox.flatMap(state.paintBounds(of:)))
    }

    /// `other`'s command at `index`, under its state there and with its
    /// bounds: a command moved from one list to another as it is.
    mutating func append(_ index: Int, of other: DisplayList) {
        append(other.commands[index], under: other.state(at: index), bounds: other.bounds[index])
    }

    private mutating func append(_ command: DrawCommand, under state: DrawState, bounds: Rect?) {
        version = nil
        if states.last != state {
            states.append(state)
        }
        stateIndices.append(Int32(states.count - 1))
        commands.append(command)
        self.bounds.append(bounds)
    }

    public mutating func append(contentsOf other: DisplayList) {
        guard !other.commands.isEmpty else { return }
        // Into an empty list: that list, as it is — its storage and its
        // version with it.
        guard !commands.isEmpty else {
            self = other
            return
        }
        version = nil
        // Its first run goes on with this list's last, when they share a
        // state — the list it would have been, built in one.
        let joins = states.last == other.states[0]
        let offset = Int32(states.count) - (joins ? 1 : 0)
        states.append(contentsOf: other.states[(joins ? 1 : 0)...])
        if offset == 0 {
            stateIndices.append(contentsOf: other.stateIndices)
        } else {
            stateIndices.append(contentsOf: other.stateIndices.lazy.map { $0 + offset })
        }
        commands.append(contentsOf: other.commands)
        bounds.append(contentsOf: other.bounds)
    }

    /// Whether `commands[index]` draws what `other.commands[otherIndex]`
    /// does, under the same state — wherever in their lists the two stand.
    func draws(_ index: Int, as otherIndex: Int, in other: DisplayList) -> Bool {
        states[Int(stateIndices[index])] == other.states[Int(other.stateIndices[otherIndex])]
            && commands[index] == other.commands[otherIndex]
    }

    public static func == (lhs: DisplayList, rhs: DisplayList) -> Bool {
        if let version = lhs.version, version == rhs.version { return true }
        return lhs.stateIndices == rhs.stateIndices && lhs.states == rhs.states && lhs.commands == rhs.commands
    }

    /// The same list drawn `(dx, dy)` further along — how a view's absolute
    /// commands become local to its own render node, so that the node's
    /// content compares equal across passes that only *moved* the view.
    /// Each state is moved once, for every command under it.
    func translated(dx: Double, dy: Double) -> DisplayList {
        guard dx != 0 || dy != 0 else { return self }
        var copy = self
        copy.states = states.map { $0.translated(dx: dx, dy: dy) }
        copy.commands = commands.map { $0.translated(dx: dx, dy: dy) }
        copy.bounds = bounds.map { $0?.offsetBy(dx: dx, dy: dy) }
        // Moved once, it is still the kept list, there; moved again, the
        // sums of two moves need not be the moves of one.
        if let version, version.dx == 0, version.dy == 0 {
            copy.version = Version(kept: version.kept, dx: dx, dy: dy)
        } else {
            copy.version = nil
        }
        return copy
    }

    /// The same list with `transform` applied after each command's own:
    /// how a `.shader` layer takes a scaled view's commands back to its
    /// frame's size. A move and a scale without a flip only — what keeps a
    /// clip, a rect on screen, a rect. The commands stay as they are; only
    /// the states change.
    func transformed(by transform: Transform) -> DisplayList {
        guard !transform.isIdentity else { return self }
        var copy = self
        copy.states = states.map { $0.transformed(by: transform) }
        copy.version = nil
        for index in commands.indices {
            copy.bounds[index] = commands[index].paintBox.flatMap(copy.state(at: index).paintBounds(of:))
        }
        return copy
    }

    /// The box every command in the list can paint in, or `nil` for a list
    /// that paints nothing.
    var paintBounds: Rect? {
        var result: Rect?
        for case let rect? in bounds {
            result = result.map { $0.union(rect) } ?? rect
        }
        return result
    }
}

extension DrawContext {
    /// The clip and transform a command placed here is drawn under.
    var drawState: DrawState {
        DrawState(transform: transform, clip: clip, clipCornerRadius: clipCornerRadius, transformedClips: transformedClips)
    }
}

/// The ambient state a node draws under: inherited opacity, clip and
/// transform, plus the environment-driven defaults a leaf needs. Passed down
/// `place`, never up.
public struct DrawContext: Sendable {
    public var opacity: Double = 1
    public var transform: Transform = .identity
    public var clip: Rect?
    public var clipCornerRadius: Double = 0

    /// True while the list being filled is a *capture* that wants every
    /// pixel of the subtree in it — a `.shader` layer, a `.hidden()` view's
    /// discard, a drag snapshot. A `.drawingGroup()` inside then draws
    /// inline instead of into a node of its own, which would composite over
    /// the capture rather than into it.
    var flattensRenderNodes = false

    /// The clip of the containers above the nearest enclosing render node,
    /// which took it out of `clip` so its content compares equal as it
    /// scrolls under the clip and cuts it at the composite instead. A node
    /// or shader slot inside is cut by this and by `clip` both.
    var nodeClip: Rect?

    /// True inside a view being drawn where it was, not where layout puts
    /// it — a removed view exiting, a drag snapshot. Nothing inside starts
    /// or follows motion, and no node's remembered rect is disturbed.
    var freezesMotion = false

    /// Set while a leaving transition slot is drawn: the node over the
    /// child its body stands on, which freezes that child — and only that
    /// one — while the body around it keeps moving.
    var frozenTransitionContent: ObjectIdentifier?

    /// What holds a reference and is set in few places — a rotated clip, a
    /// shader effect, an animation, a scroll view — behind one object, which
    /// the rest of the tree passes along as it is: every node copies its
    /// context, and a copy then retains one reference, not one for each.
    /// Setting a value makes a new one; setting the value it holds keeps it.
    private(set) var shared = Shared.none

    final class Shared: Sendable {
        let transformedClips: [TransformedClip]
        let shaderCanvasInput: ShaderCanvasInput?
        let animation: Animation?
        let coordinateSpaces: [CoordinateSpaceFrame]

        static let none = Shared(transformedClips: [], shaderCanvasInput: nil, animation: nil, coordinateSpaces: [])

        init(
            transformedClips: [TransformedClip],
            shaderCanvasInput: ShaderCanvasInput?,
            animation: Animation?,
            coordinateSpaces: [CoordinateSpaceFrame]
        ) {
            self.transformedClips = transformedClips
            self.shaderCanvasInput = shaderCanvasInput
            self.animation = animation
            self.coordinateSpaces = coordinateSpaces
        }
    }

    /// Clips set under a rotation, which no rect on screen can stand for —
    /// `clip` holds the box around them.
    public var transformedClips: [TransformedClip] {
        get { shared.transformedClips }
        set {
            guard newValue != shared.transformedClips else { return }
            shared = Shared(
                transformedClips: newValue, shaderCanvasInput: shared.shaderCanvasInput,
                animation: shared.animation, coordinateSpaces: shared.coordinateSpaces
            )
        }
    }

    /// Set by a `.shader` effect for the view it is applied to: a canvas
    /// node placed inside (`ThorCanvas`, `ThorCanvasRender`) reports itself
    /// here instead of compositing, so its image can be the effect's input.
    var shaderCanvasInput: ShaderCanvasInput? {
        get { shared.shaderCanvasInput }
        set {
            guard newValue !== shared.shaderCanvasInput else { return }
            shared = Shared(
                transformedClips: shared.transformedClips, shaderCanvasInput: newValue,
                animation: shared.animation, coordinateSpaces: shared.coordinateSpaces
            )
        }
    }

    /// How a node placed somewhere new in this pass moves there — the
    /// transaction's animation, or `.animation(_:value:)`'s below it. Only
    /// set in a pass that built something; `nil` means it jumps.
    var animation: Animation? {
        get { shared.animation }
        set {
            guard newValue != shared.animation else { return }
            shared = Shared(
                transformedClips: shared.transformedClips, shaderCanvasInput: shared.shaderCanvasInput,
                animation: newValue, coordinateSpaces: shared.coordinateSpaces
            )
        }
    }

    /// The coordinate spaces named above this point — by `.coordinateSpace`
    /// and by every scroll view — with where each was placed, innermost
    /// last, for a `GeometryProxy` to measure in.
    var coordinateSpaces: [CoordinateSpaceFrame] {
        get { shared.coordinateSpaces }
        set {
            guard newValue != shared.coordinateSpaces else { return }
            shared = Shared(
                transformedClips: shared.transformedClips, shaderCanvasInput: shared.shaderCanvasInput,
                animation: shared.animation, coordinateSpaces: newValue
            )
        }
    }

    /// What a render node or shader slot placed here is cut to at the
    /// composite: every clip above it, whichever node took it over.
    var compositeClip: Rect? {
        switch (clip, nodeClip) {
        case (let clip?, let outer?): return clip.intersection(outer)
        case (let clip?, nil): return clip
        case (nil, let outer?): return outer
        case (nil, nil): return nil
        }
    }

    /// Where `rect`, a frame in layout space, shows under `transform`, for
    /// a node whose image the engine composites into a rect — a shader
    /// slot, a texture, a canvas node. Drawn commands carry the transform;
    /// such a node has only this rect, so it is how the node follows a
    /// stack's slide, an `.offset` or a `.scaleEffect`.
    ///
    /// A move or a scale gives `rect` under the transform exactly. The
    /// composite can only place an image in a rect, not turn it: under a
    /// rotation the frame's center goes where the transform takes it, at
    /// the size the transform scales it to, and stays level.
    func compositeFrame(of rect: Rect) -> Rect {
        let t = transform
        guard !t.isIdentity else { return rect }
        let width = rect.width * (t.e11 * t.e11 + t.e21 * t.e21).squareRoot()
        let height = rect.height * (t.e12 * t.e12 + t.e22 * t.e22).squareRoot()
        if t.e12 == 0 && t.e21 == 0 {
            // From the corner the transform takes to the top-left, so a
            // move leaves the size exactly as it was.
            let x = t.e11 * (t.e11 < 0 ? rect.maxX : rect.minX) + t.e13
            let y = t.e22 * (t.e22 < 0 ? rect.maxY : rect.minY) + t.e23
            return Rect(x: x, y: y, width: width, height: height)
        }
        let center = t.apply(to: Point(x: rect.midX, y: rect.midY))
        return Rect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    public init() {}

    /// `color` faded by the inherited opacity — every leaf applies this
    /// rather than the renderer setting per-paint opacity, so gradients fade
    /// too.
    func resolve(_ color: Color) -> Color {
        opacity >= 1 ? color : color.opacity(opacity)
    }

    /// `paint` faded the same way. Styles are resolved when their views are
    /// built, against the environment, color scheme included; what is left
    /// for drawing is the opacity a pass inherits. A paint at full opacity
    /// is drawn as it is: fading a gradient's stops by 1 would only copy
    /// them.
    func resolve(_ paint: _ResolvedPaint) -> _ResolvedPaint {
        paint.opacity(opacity)
    }

    /// Narrow the clip to `rect`, a frame in layout space, as `transform`
    /// shows it — intersecting, so an inner clip can never widen an outer
    /// one. Under a scale or a move the frame is still a rect on screen;
    /// under a rotation it is not, and rides along as a transformed clip.
    func clipped(to rect: Rect, cornerRadius: Double = 0) -> DrawContext {
        guard !transform.isIdentity else { return clipped(onScreen: rect, cornerRadius: cornerRadius) }
        let sx = abs(transform.e11), sy = abs(transform.e22)
        let axisAligned = transform.e12 == 0 && transform.e21 == 0
        if axisAligned && (cornerRadius == 0 || sx == sy) {
            let radius = cornerRadius.isInfinite || cornerRadius == 0 ? cornerRadius : cornerRadius * sx
            return clipped(onScreen: rect.applying(transform), cornerRadius: radius)
        }
        // The box around it still bounds what can show, for culling and
        // for the scissor a render node composites under.
        var copy = clipped(onScreen: rect.applying(transform))
        copy.transformedClips.append(TransformedClip(rect: rect, cornerRadius: cornerRadius, transform: transform))
        return copy
    }

    private func clipped(onScreen rect: Rect, cornerRadius: Double = 0) -> DrawContext {
        var copy = self
        copy.clip = clip.map { $0.intersection(rect) } ?? rect
        // Only one rounded clip is tracked; an inner rounding replaces an
        // outer one rather than compositing two rounded masks.
        copy.clipCornerRadius = cornerRadius > 0 ? cornerRadius : (clip == nil ? 0 : clipCornerRadius)
        return copy
    }
}
