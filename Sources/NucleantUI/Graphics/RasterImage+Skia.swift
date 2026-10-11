//
//  RasterImage+Skia.swift
//  NucleantUI
//
//  Decoding on Linux, Android and WebAssembly: Skia's SkCodec, which every
//  platform's Skia is built with — PNG on all of them. The pixels go straight
//  from the decoder into the buffer; nothing is drawn.
//

#if !os(macOS) && !os(iOS)
import Foundation
import NucleantSkia

extension RasterImage {
    /// Decoded from a PNG, or any other file this platform's Skia has a
    /// decoder for. `nil` when the file is missing or not an image.
    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url),
              let codec = data.withUnsafeBytes({ SkCodec.makeFromData($0) }),
              let pixels = codec.getPixels(colorType: .bgra8888, alphaType: .premul) else {
            return nil
        }
        self.init(width: Int(codec.width()), height: Int(codec.height()), pixels: pixels)
    }
}
#endif
