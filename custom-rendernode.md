# Custom render node

Copy `Sources/NucleantUI/App/NucleantRenderNode.swift`, rename the class, add your cases.

## 1. The node

```swift
import CVulkan
import NucleantVulkan
import NucleantThorVG
import NucleantSkia
import NucleantUI

public final class MyRenderNode: NucleantContainerNode, @unchecked Sendable {

    public enum Context: NucleantNodeContext {
        public typealias Node = MyRenderNode

        // Required — all 7, unchanged
        case thor(ThorShaderNode<MyRenderNode>)
        case skia(SkiaShaderNode<MyRenderNode>)
        case compute(ComputeShaderNode<MyRenderNode>)
        case vertexShader(VertFragShaderNode<MyRenderNode>)
        case image(ImageNode<MyRenderNode>)
        case externalTexture(ExternalTextureNode<MyRenderNode>)
        case renderTexture(RenderTextureNode<MyRenderNode>)

        // Yours
        case myNode(MyShaderNode<MyRenderNode>)
    }

    public let id: Int
    public let context: Context
    public var needsRender: Bool = true
    public var compositeRect: SIMD4<Double>?
    public var compositeScissor: SIMD4<Double>?
    public var compositesToWindow: Bool = true

    public init(id: Int, context: Context) {
        self.id = id
        self.context = context
    }

    public func observeContext() {
        switch context {
        case .thor(let node): observe(node)
        case .skia(let node): observe(node)
        case .compute(let node): observe(node)
        case .vertexShader(let node): observe(node)
        case .image(let node): observe(node)
        case .externalTexture(let node): observe(node)
        case .renderTexture(let node): observe(node)
        case .myNode(let node): observe(node)
        }
    }

    public func update(engine: Engine, cmd: VkCommandBuffer) {
        guard needsRender else { return }
        switch context {
        case .thor(let node): node.update(engine, slot: self, cmd: cmd)
        case .skia(let node): node.update(engine, slot: self, cmd: cmd)
        case .compute(let node): node.update(engine, slot: self, cmd: cmd)
        case .vertexShader(let node): node.update(engine, slot: self, cmd: cmd)
        case .image(let node): node.update(engine, slot: self, cmd: cmd)
        case .externalTexture(let node): node.update(engine, slot: self, cmd: cmd)
        case .renderTexture(let node): node.update(engine, slot: self, cmd: cmd)
        case .myNode(let node): node.update(engine, slot: self, cmd: cmd)
        }
        needsRender = false
    }

    public func destroyResources(engine: Engine) {
        switch context {
        case .thor(let node): node.destroyResources(engine)
        case .skia(let node): node.destroyResources(engine)
        case .compute(let node): node.destroyResources(engine)
        case .vertexShader(let node): node.destroyResources(engine)
        case .image(let node): node.destroyResources(engine)
        case .externalTexture(let node): node.destroyResources(engine)
        case .renderTexture(let node): node.destroyResources(engine)
        case .myNode(let node): node.destroyResources(engine)
        }
    }

    public func getImageView() -> VkImageView? {
        guard compositesToWindow else { return nil }
        switch context {
        case .thor(let node): return node.imageView
        case .skia(let node): return node.imageView
        case .compute(let node): return node.imageView
        case .vertexShader(let node): return node.imageView
        case .image(let node): return node.imageView
        case .externalTexture(let node): return node.imageView
        case .renderTexture(let node): return node.imageView
        case .myNode(let node): return node.imageView
        }
    }

    public func resizeToFitWindow(width: Int, height: Int, engine: Engine) {
        switch context {
        case .thor(let node) where compositesToWindow && compositeRect == nil:
            engine.resizeThorNode(node, id: id, width: width, height: height)
        case .skia(let node) where compositesToWindow && compositeRect == nil:
            engine.resizeSkiaNode(node, id: id, width: width, height: height)
        case .thor, .skia, .compute, .vertexShader, .image, .externalTexture, .renderTexture:
            break
        case .myNode:
            break // or resize yours
        }
    }
}
```

The only new code is your own cases' arms in the 5 switches. Everything else is pasted as-is.

## 2. Use it

```swift
@main
struct MyApp: NucleantApp {
    typealias RenderNode = MyRenderNode
    var body: some Scene { ... }
}
```

Or once for every app, through a protocol of your own (see `KivyApp`):

```swift
public protocol MyAppProtocol: NucleantApp where RenderNode == MyRenderNode {}
```

## Not working yet

The views reach the registry through `ShaderHost`, which is still typed `NucleantRenderNode`. With a custom node, the window and engine run on it, but the views get no registry (logged).
