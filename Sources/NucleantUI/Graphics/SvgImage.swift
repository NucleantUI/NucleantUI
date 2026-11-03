//
//  SvgImage.swift
//  NucleantUI
//
//  An SVG document, the vector picture an `SvgView` draws. Parsed once by
//  Skia's SVG module (SkSVGDOM), which every platform's Skia is built with,
//  and never changed after — so one document can sit behind any number of
//  views and display lists, drawn at whatever size each asks for.
//

import Foundation
import NucleantSkia

/// A parsed SVG document, ready to draw at any size.
///
/// ```swift
/// let icon = SvgImage(contentsOf: url)!
/// SvgView(icon)                                  // at the document's own size
/// SvgView(icon).resizable().frame(width: 96, height: 96)
/// ```
///
/// Its `size` is what the outermost `<svg>` says it is: its `width` and
/// `height`, or its `viewBox` where those are left out.
public final class SvgImage: @unchecked Sendable {
    /// The document's own size in points — `width` × `height`; either one
    /// missing or given in percent, the `viewBox`'s size; no `viewBox`
    /// either, 300 × 150, the size a browser gives an SVG that says nothing
    /// about its size.
    public let size: Size

    /// The parsed document, its viewport set to `size` once, here. Only
    /// ever rendered after that, which leaves it as it is — the reason
    /// sharing it is safe.
    let document: SkSVGDOM

    /// The source, for a renderer that parses SVG itself (ThorVG).
    let data: [UInt8]

    /// The document in `data`. `nil` when it isn't SVG.
    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard let document = bytes.withUnsafeBytes({ SkSVGDOM.make($0) }) else { return nil }
        let size = Self.naturalSize(of: document)
        document.setContainerSize(SIMD2<Float>(size))
        self.document = document
        self.data = bytes
        self.size = size
    }

    /// The document in the file at `url`. `nil` when the file is missing or
    /// isn't SVG.
    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    /// The document written out in `markup` — `"<svg …>…</svg>"`. `nil` when
    /// it isn't SVG.
    public convenience init?(markup: String) {
        self.init(data: Data(markup.utf8))
    }

    /// Skia gives no intrinsic size at all — 0 × 0 — when either of `width`
    /// and `height` is a percentage, which is also what a missing one is.
    private static func naturalSize(of document: SkSVGDOM) -> Size {
        let intrinsic = document.intrinsicSize()
        if intrinsic.x > 0, intrinsic.y > 0 {
            return Size(width: Double(intrinsic.x), height: Double(intrinsic.y))
        }
        if let box = document.viewBox(), box.size.x > 0, box.size.y > 0 {
            return Size(width: Double(box.size.x), height: Double(box.size.y))
        }
        return Size(width: 300, height: 150)
    }

    /// Where the document lands when drawn into `frame`: as large as fits,
    /// in proportion, centered — what an `<svg>` does in a browser's box.
    func fittedRect(in frame: Rect) -> Rect {
        guard size.width > 0, size.height > 0 else { return Rect(origin: frame.center, size: .zero) }
        let scale = min(frame.width / size.width, frame.height / size.height)
        let fitted = size * max(scale, 0)
        return Rect(origin: frame.origin + (frame.size - fitted) / 2, size: fitted)
    }
}

extension SvgImage: Hashable {
    /// By identity: the document never changes, so the same object is the
    /// same picture.
    public static func == (lhs: SvgImage, rhs: SvgImage) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

extension SvgImage: ViewInput {
    public func _isEquivalent(to other: SvgImage) -> Bool { self === other }
}
