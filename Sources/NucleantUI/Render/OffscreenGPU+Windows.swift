//
//  OffscreenGPU+Windows.swift
//  NucleantUI
//
//  Windows: no windowless Vulkan device is made here yet, so `renderImage`
//  reports that it has no GPU to draw on (and returns an empty image)
//  rather than drawing nothing silently.
//
#if os(Windows)
import NucleantVulkan

extension OffscreenGPU {
    static func makeDevice() throws -> VulkanRenderDevice<NucleantRenderNode> {
        throw OffscreenGPUError.unsupportedPlatform("Windows")
    }
}
#endif
