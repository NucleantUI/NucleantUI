//
//  OffscreenGPU+Android.swift
//  NucleantUI
//
//  Android: no windowless Vulkan device is made here yet, so `renderImage`
//  reports that it has no GPU to draw on (and returns an empty image)
//  rather than drawing nothing silently.
//
#if os(Android)
import NucleantVulkan

extension OffscreenGPU {
    static func makeDevice() throws -> VulkanRenderDevice<NucleantRenderNode> {
        throw OffscreenGPUError.unsupportedPlatform("Android")
    }
}
#endif
