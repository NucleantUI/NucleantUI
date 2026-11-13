//
//  OffscreenGPU.swift
//  NucleantUI
//
//  The GPU `renderImage` draws on. A snapshot is a Vulkan render like any
//  other: Skia draws the display list into an image on a Vulkan device,
//  through the same `SkiaDisplayRenderer` the window uses, and the pixels
//  are read back once the GPU is done with them.
//
//  The device is this one's own, made without a window the first time an
//  image is asked for and kept for the process. A snapshot then works
//  before the first window, after the last, and where there is no window
//  at all, such as a test. Making that device is the one part each
//  platform does its own way (`OffscreenGPU+<Platform>.swift`).
//

import CVulkan
import NucleantSkia
import NucleantVulkan

/// Why `renderImage` has no GPU to draw on.
enum OffscreenGPUError: Error {
    /// No windowless Vulkan device is made on this platform yet.
    case unsupportedPlatform(String)
}

@MainActor
final class OffscreenGPU {

    /// The one every `renderImage` draws on.
    static let shared = OffscreenGPU()

    private var device: VulkanRenderDevice<NucleantRenderNode>?
    /// One Ganesh context on the device, so Skia's caches (glyphs,
    /// pipelines) are built once for every snapshot rather than once each.
    private var context: SkiaVulkanContext?
    /// Set when making the device or the context failed: reported once,
    /// not tried again on every call.
    private var failure: String?

    /// `list` (points, origin at the top-left) drawn into a `width × height`
    /// image at `scale` pixels per point, and read back. nil, logged, when
    /// there is no GPU to draw on or the draw failed.
    func image(of list: DisplayList, width: Int, height: Int, scale: Double) -> RasterImage? {
        guard let (device, context) = ready() else { return nil }
        guard let node = device.makeSkiaWidgetNode(context: context, width: width, height: height),
              let surface = node.canvas.surface
        else {
            nucleantLogError("NucleantUI: renderImage — no \(width)x\(height) Skia surface on the GPU\n")
            return nil
        }
        defer { node.destroyResources(device) }

        let renderer = SkiaDisplayRenderer(node: node)
        renderer.scale = scale
        renderer.render(list)
        // Submitted and waited for, and left where a node's update leaves
        // its image, which is where the device reads pixels back from.
        // UInt32(...): a Vulkan enum's raw value is Int32 on Windows.
        guard surface.flush(finalLayout: UInt32(VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL.rawValue), syncCpu: true),
              let bytes = device.readPixels(of: node.image, width: width, height: height)
        else {
            nucleantLogError("NucleantUI: renderImage — the \(width)x\(height) GPU image could not be drawn or read back\n")
            return nil
        }

        // R, G, B, A bytes, premultiplied, as the RGBA image holds them;
        // `RasterImage` is premultiplied ARGB words.
        var pixels = [UInt32](repeating: 0, count: width * height)
        for index in pixels.indices {
            let r = UInt32(bytes[index * 4])
            let g = UInt32(bytes[index * 4 + 1])
            let b = UInt32(bytes[index * 4 + 2])
            let a = UInt32(bytes[index * 4 + 3])
            pixels[index] = (a << 24) | (r << 16) | (g << 8) | b
        }
        return RasterImage(width: width, height: height, pixels: pixels)
    }

    /// The device and its Skia context, made on first use.
    private func ready() -> (VulkanRenderDevice<NucleantRenderNode>, SkiaVulkanContext)? {
        if let device, let context { return (device, context) }
        guard failure == nil else { return nil }
        do {
            let device = try self.device ?? Self.makeDevice()
            self.device = device
            let context = try device.makeSkiaContext()
            self.context = context
            return (device, context)
        } catch {
            failure = "\(error)"
            nucleantLogError("NucleantUI: renderImage — no GPU to draw on: \(error)\n")
            return nil
        }
    }
}
