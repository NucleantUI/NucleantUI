//
//  RasterImage+Apple.swift
//  NucleantUI
//
//  Decoding on macOS and iOS: ImageIO, drawn into a bitmap by CoreGraphics.
//

#if os(macOS) || os(iOS)
import Foundation
import ImageIO
import CoreGraphics

extension RasterImage {
    /// Decoded from a PNG, JPEG or any other file ImageIO reads. `nil` when
    /// the file is missing or not an image.
    public convenience init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        self.init(image)
    }

    /// `image` drawn into a premultiplied BGRA buffer, which is ARGB8888
    /// read as little-endian words.
    public convenience init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }
}
#endif
