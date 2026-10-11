//
//  BrowserTests.swift
//  NucleantUITests
//
//  NucleantUI in the browser (wasm only), on a real page: a window is a
//  <canvas>, its engine is Vulkan on the page's WebGPU, Skia (Graphite) draws
//  the tree through the same WebGPU, and the bundled fonts come from the
//  resource bundles the page mounts at NUCLEANT_APP_PATH; the window follows
//  the page's light/dark preference. Also what the platform's Foundation
//  lacks and the framework fills in. Run with
//  scripts/run_wasm_tests.py (headless Chrome).
//
#if os(WASI)
import Foundation
import Testing
import CVulkan
import NucleantVulkan
import Platform_Wasm
@testable import NucleantUI

@Suite(.serialized)
@MainActor
struct BrowserTests {

    init() {
        ThorEngine.ensureInitialized()
    }

    // MARK: Identity

    @Test func viewIDsAreDistinctPerPlaceAndStableAtOne() {
        // The macro's 64-bit hash, narrowed to this target's 32-bit Int.
        let first = #viewID
        let second = #viewID
        #expect(first != second)
        #expect(first != .unknown)
        let repeated = (0..<2).map { _ in site() }
        #expect(repeated[0] == repeated[1])
        #expect(repeated[0] != first)
    }

    private func site(_ id: ViewID = #viewID) -> ViewID { id }

    // MARK: Foundation stand-ins

    @Test func localizedStandardIsTheLexicalOrderHere() {
        let names = ["beta", "Alpha", "alpha", "Beta"]
        #expect(names.sorted(using: String.StandardComparator.localizedStandard)
                == names.sorted(using: String.StandardComparator.lexical))
    }

    @Test func formattersParseNumbersAndDates() {
        var object: AnyObject?
        let numbers = NumberFormatter()
        #expect(numbers.getObjectValue(&object, for: "42", errorDescription: nil))
        #expect((object as? NSNumber)?.intValue == 42)
        #expect(!numbers.getObjectValue(&object, for: "forty-two", errorDescription: nil))

        let dates = DateFormatter()
        dates.dateFormat = "yyyy-MM-dd"
        dates.timeZone = TimeZone(identifier: "UTC")
        #expect(dates.getObjectValue(&object, for: "2026-10-10", errorDescription: nil))
        #expect((object as? NSDate)?.timeIntervalSince1970 == 1_791_590_400)

        #expect(!Formatter().getObjectValue(&object, for: "anything", errorDescription: nil))
    }

    // MARK: Fonts

    @Test func bundledFacesLoadFromTheMountedResources() throws {
        let root = try #require(ProcessInfo.processInfo.environment["NUCLEANT_APP_PATH"])
        #expect(FontRegistry.resolve(.system(size: 13)) == "Roboto")
        #expect(FontRegistry.path(ofResolved: "Roboto") == "\(root)/NucleantUI_NucleantUI.resources/Fonts/Roboto-Regular.ttf")
        #expect(FontRegistry.resolve(.system(size: 13, design: .monospaced)) == "Roboto Mono")
        #expect(FontRegistry.resolve(.system(size: 13, weight: .bold)) == "Roboto Bold")
    }

    @Test func bundleModuleFindsTheMountedResources() throws {
        // SwiftPM's generated accessor looks only at paths on the machine
        // that built the module; the page mounts the bundles at the build
        // directory too (resources.json's buildRoot). Read by path: this
        // Foundation's lookups in a subdirectory drop the name's last
        // character ("Fonts/Roboto-Regular.tt").
        #expect(Bundle.module.bundleURL.lastPathComponent == "NucleantUI_NucleantUI.resources")
        let data = try Data(contentsOf: Bundle.module.bundleURL.appendingPathComponent("Fonts/Roboto-Regular.ttf"))
        #expect(Array(data.prefix(4)) == [0x00, 0x01, 0x00, 0x00])   // a TrueType font
    }

    // MARK: Windows

    @Test func windowDrawsItsTreeIntoACanvasOnThePage() async throws {
        let window = HostingWindow(title: "browser", width: 120, height: 80, root: Color(red: 1, green: 0, blue: 0))
        try window.present()
        defer { window.platformWindow?.close() }
        let platformWindow = try #require(window.platformWindow)
        let engine = try #require(window.renderEngine)
        #expect(platformWindow.width == 120)
        #expect(platformWindow.height == 80)

        // The page ticks the window (requestAnimationFrame) while this sleeps.
        try await Task.sleep(for: .milliseconds(300))

        let slot = try #require(engine.nodes.first { $0.compositesToWindow && $0.compositeRect == nil })
        #expect(engine.readable.contains(slot.id))
        // The window canvas is the primary renderer's: Skia (RGBA), or
        // ThorVG (BGRA) in a build without SKIA_MODE.
        let image: VkImage, width: Int, height: Int, red: [UInt8]
        switch slot.context {
        case .skia(let canvas):
            (image, width, height, red) = (canvas.image, Int(canvas.width), Int(canvas.height), [255, 0, 0, 255])
        case .thor(let canvas):
            (image, width, height, red) = (canvas.image, Int(canvas.width), Int(canvas.height), [0, 0, 255, 255])
        default:
            Issue.record("the window canvas is neither a Skia nor a ThorVG node")
            return
        }
        #expect(width == Int(platformWindow.bufferWidth))
        #expect(height == Int(platformWindow.bufferHeight))
        // The root fills the window red.
        let pixels = readPixels(engine, image, width: width, height: height)
        let center = ((height / 2) * width + width / 2) * 4
        #expect(Array(pixels[center..<center + 4]) == red)
    }

    @Test func windowFollowsThePagesColorScheme() async throws {
        let window = HostingWindow(title: "appearance", width: 120, height: 80, root: Color.background)
        try window.present()
        defer { window.platformWindow?.close() }
        let engine = try #require(window.renderEngine)
        let original = BrowserAppearance.colorScheme()
        defer { nucleantColorSchemeChanged(original.rawValue) }

        // scripts/run_wasm_tests.py starts Chrome with a dark page.
        #expect(window.host.environment.colorScheme == .dark)
        try await Task.sleep(for: .milliseconds(300))
        expectCenter(engine, is: Color.background.resolved(for: .dark))

        // The page's media-query listener reports a switch to light, then back.
        nucleantColorSchemeChanged(0)
        #expect(window.host.environment.colorScheme == .light)
        try await Task.sleep(for: .milliseconds(300))
        expectCenter(engine, is: Color.background.resolved(for: .light))

        nucleantColorSchemeChanged(1)
        #expect(window.host.environment.colorScheme == .dark)
        try await Task.sleep(for: .milliseconds(300))
        expectCenter(engine, is: Color.background.resolved(for: .dark))
    }

    /// The window canvas's center pixel is `color`, to within 8-bit rounding.
    private func expectCenter(_ engine: NucleantRenderEngine, is color: Color,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        guard let slot = engine.nodes.first(where: { $0.compositesToWindow && $0.compositeRect == nil }) else {
            Issue.record("no window canvas", sourceLocation: sourceLocation)
            return
        }
        // Skia's canvas is RGBA, ThorVG's (a build without SKIA_MODE) BGRA.
        let image: VkImage, width: Int, height: Int, channels: [Int]
        switch slot.context {
        case .skia(let canvas):
            (image, width, height, channels) = (canvas.image, Int(canvas.width), Int(canvas.height), [0, 1, 2, 3])
        case .thor(let canvas):
            (image, width, height, channels) = (canvas.image, Int(canvas.width), Int(canvas.height), [2, 1, 0, 3])
        default:
            Issue.record("the window canvas is neither a Skia nor a ThorVG node", sourceLocation: sourceLocation)
            return
        }
        let pixels = readPixels(engine, image, width: width, height: height)
        let center = ((height / 2) * width + width / 2) * 4
        let expected = [color.red, color.green, color.blue, color.alpha].map { Int(($0 * 255).rounded()) }
        let actual = channels.map { Int(pixels[center + $0]) }
        #expect(zip(actual, expected).allSatisfy { abs($0 - $1) <= 1 }, "\(actual) is not \(expected)",
                sourceLocation: sourceLocation)
    }
}

/// `image`'s texels through a host-visible buffer on the engine's device.
private func readPixels(_ engine: NucleantRenderEngine, _ image: VkImage, width: Int, height: Int) -> [UInt8] {
    let byteCount = width * height * 4
    var bufferInfo = VkBufferCreateInfo()
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
    bufferInfo.size = VkDeviceSize(byteCount)
    bufferInfo.usage = VkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue)
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE
    var buffer: VkBuffer?
    vkCreateBuffer(engine.device, &bufferInfo, nil, &buffer)
    defer { vkDestroyBuffer(engine.device, buffer, nil) }

    var requirements = VkMemoryRequirements()
    vkGetBufferMemoryRequirements(engine.device, buffer, &requirements)
    var properties = VkPhysicalDeviceMemoryProperties()
    vkGetPhysicalDeviceMemoryProperties(engine.physicalDevice, &properties)
    let wanted = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue
    let memoryType = withUnsafeBytes(of: properties.memoryTypes) { raw -> UInt32 in
        let types = raw.bindMemory(to: VkMemoryType.self)
        for index in 0..<Int(properties.memoryTypeCount)
        where requirements.memoryTypeBits & (1 << index) != 0 && types[index].propertyFlags & wanted == wanted {
            return UInt32(index)
        }
        return 0
    }
    var allocInfo = VkMemoryAllocateInfo()
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
    allocInfo.allocationSize = requirements.size
    allocInfo.memoryTypeIndex = memoryType
    var memory: VkDeviceMemory?
    vkAllocateMemory(engine.device, &allocInfo, nil, &memory)
    defer { vkFreeMemory(engine.device, memory, nil) }
    vkBindBufferMemory(engine.device, buffer, memory, 0)

    engine.oneTimeSubmit { cmd in
        var region = VkBufferImageCopy()
        region.imageSubresource = VkImageSubresourceLayers(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue), mipLevel: 0, baseArrayLayer: 0, layerCount: 1)
        region.imageExtent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        vkCmdCopyImageToBuffer(cmd, image, VK_IMAGE_LAYOUT_GENERAL, buffer, 1, &region)
    }

    var out = [UInt8](repeating: 0, count: byteCount)
    var mapped: UnsafeMutableRawPointer?
    vkMapMemory(engine.device, memory, 0, VkDeviceSize(byteCount), 0, &mapped)
    if let mapped {
        out.withUnsafeMutableBytes { $0.baseAddress?.copyMemory(from: mapped, byteCount: byteCount) }
    }
    vkUnmapMemory(engine.device, memory)
    return out
}
#endif
