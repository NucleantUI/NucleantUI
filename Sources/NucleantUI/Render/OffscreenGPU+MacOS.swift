//
//  OffscreenGPU+MacOS.swift
//  NucleantUI
//
//  macOS: the windowless MoltenVK device NucleantVulkan makes, the same
//  kind the app makes for its windows to share.
//
#if os(macOS)
import NucleantVulkan

extension OffscreenGPU {
    static func makeDevice() throws -> VulkanRenderDevice<NucleantRenderNode> {
        try VulkanRenderDevice<NucleantRenderNode>()
    }
}
#endif
