//
//  RasterImage.swift
//  NucleantUI
//
//  A decoded bitmap, the pixels an `Image` view draws. Immutable once made,
//  so one image can sit behind any number of views and display lists.
//  `init?(contentsOf:)`, the decoding, is per platform: ImageIO on Apple
//  (RasterImage+Apple.swift), Skia's SkCodec elsewhere (RasterImage+Skia.swift).
//

import Foundation

/// `width` × `height` pixels, row-major from the top-left, each an
/// alpha-premultiplied ARGB `UInt32` — ThorVG's `ARGB8888`, which is also
/// what a little-endian BGRA byte buffer reads as.
public final class RasterImage: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt32]

    public init(width: Int, height: Int, pixels: [UInt32]) {
        precondition(pixels.count == width * height, "RasterImage: \(pixels.count) pixels for \(width)×\(height)")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The pixel size as points — an image is drawn at one point per
    /// pixel unless it is `.resizable()`.
    public var size: Size { Size(width: Double(width), height: Double(height)) }

    /// The pixels inside `rect` (pixel coordinates, clamped to the image)
    /// as an image of their own — one cell of a sprite sheet.
    public func cropped(to rect: Rect) -> RasterImage {
        let x0 = max(0, min(width, Int(rect.minX.rounded())))
        let y0 = max(0, min(height, Int(rect.minY.rounded())))
        let x1 = max(x0, min(width, Int(rect.maxX.rounded())))
        let y1 = max(y0, min(height, Int(rect.maxY.rounded())))
        let w = x1 - x0, h = y1 - y0
        var out = [UInt32](repeating: 0, count: w * h)
        pixels.withUnsafeBufferPointer { source in
            out.withUnsafeMutableBufferPointer { target in
                for row in 0..<h {
                    let from = (y0 + row) * width + x0
                    target.baseAddress!.advanced(by: row * w)
                        .update(from: source.baseAddress!.advanced(by: from), count: w)
                }
            }
        }
        return RasterImage(width: w, height: h, pixels: out)
    }
}

extension RasterImage: Hashable {
    /// By identity: the pixels never change, so the same object is the same
    /// image, and comparing megabytes of pixels per frame would be waste.
    public static func == (lhs: RasterImage, rhs: RasterImage) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

extension RasterImage: ViewInput {
    public func _isEquivalent(to other: RasterImage) -> Bool { self === other }
}
