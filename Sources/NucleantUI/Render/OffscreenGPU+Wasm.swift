//
//  OffscreenGPU+Wasm.swift
//  NucleantUI
//
//  Wasm: no windowless Vulkan device is made here yet, so `renderImage`
//  reports that it has no GPU to draw on (and returns an empty image)
//  rather than drawing nothing silently.
//
#if os(WASI)
import NucleantVulkan

extension OffscreenGPU {
    static func makeDevice() throws -> VulkanRenderDevice<NucleantRenderNode> {
        throw OffscreenGPUError.unsupportedPlatform("Wasm")
    }
}
#endif
