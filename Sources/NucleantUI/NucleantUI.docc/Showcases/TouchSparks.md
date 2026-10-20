# Sparks over a view with a vertex stage

Draw the view and any number of glows over it in one instanced draw call.

@Metadata {
    @PageImage(purpose: card, source: "showcase-sparks", alt: "A card with a trail of orange glows drawn across it.")
}

## Overview

@Image(source: "showcase-sparks", alt: "A dark card titled Drag across the card, with a wavy trail of forty orange glows drawn over its lower half.")

A SPIR-V module with a vertex + fragment pair can be applied with `.shader`
too. It gets the same view at the same binding, but its fragment stage shades
only the pixels its triangles cover, and the rest of the rect is cleared. So
the view itself is one more instance: instance 0 is a quad over the whole
view that returns `layer(uv)`, and every instance after it is a small quad at
one spark.

- The shader is PyShader, compiled to `sparks.spv` by PyShader's build plugin
  when the app builds. ``ShaderFunction/init(spirv:isAnimated:)`` runs it with
  ``ShaderArgument``s, which is how the sparks reach it: four floats each in
  one `.floatArray`.
- There are no vertex buffers. The vertex stage picks a corner from
  `vertex_index` and a spark from `instance_index`.
- `vertices: 6` is one quad as two triangles; `instances: sparkCount + 1`
  is the view plus a quad per spark. Both are per-frame values, so a new
  spark redraws without rebuilding anything.
- `content-top-down = true` compiles `layer(uv)` for the view as `.shader`
  hands it over, stored top-down.
- Shader space counts pixels and a drag reports points, so the drag
  location is scaled by `\.displayScale` before it goes to the shader.

## The code

```toml title="pyshader.toml"
[sparks]
source = "Shaders/sparks.py"
target = "graphics"
content-top-down = true
arguments = ["sparks:floatArray"]
```

```py title="Shaders/sparks.py"
from pyshader import *

QUAD = [float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)]


class Spark:
    position: float4
    local: float2
    seed: float


def vertex(vertex_index: int, instance_index: int, resolution: float2, sparks: FloatArray) -> Spark:
    quad = QUAD
    corner = quad[vertex_index]
    if instance_index == 0:
        # The whole view, untouched.
        return Spark(float4(corner, 0.0, 1.0), corner * 0.5 + 0.5, -1.0)
    # Four floats a spark: x, y (pixels, y down), size (pixels), seed.
    s = (instance_index - 1) * 4
    centre = float2(sparks[s] / resolution.x, 1.0 - sparks[s + 1] / resolution.y) * 2.0 - 1.0
    return Spark(float4(centre + corner * sparks[s + 2] / resolution, 0.0, 1.0),
                 corner * 0.5 + 0.5, sparks[s + 3])


def fragment(uv: float2, local: float2, seed: float, time: float) -> float4:
    if seed < 0.0:
        return layer(uv)
    glow = smoothstep(0.5, 0.0, distance(local, float2(0.5)))
    flicker = 0.65 + 0.35 * sin(time * 14.0 + seed * 40.0)
    return float4(float3(1.0, 0.62, 0.25) * flicker, glow)
```

```swift
import Foundation
import NucleantUI

/// One draw call for the view and every spark over it — `sparks.spv`, which
/// the build plugin compiled from `Shaders/sparks.py`.
let sparkShader: ShaderFunction = {
    let url = Bundle.module.url(forResource: "sparks", withExtension: "spv")!
    let data = try! Data(contentsOf: url)
    return ShaderFunction(spirv: data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) })
}()

@View
struct TouchSparks {
    @Environment(\.displayScale) private var scale
    /// Four floats a spark: x, y, size, seed.
    @State private var sparks: [Float] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drag across the card").font(.headline)
            Text("Each point of the drag becomes one more instance of the same draw.")
                .foregroundColor(.secondary)
            HStack {
                Button("Clear") { sparks.removeAll() }
                Text("\(sparks.count / 4) sparks").foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420, height: 240, alignment: .topLeading)
        .background(Color.secondaryBackground)
        .cornerRadius(16)
        .shader(sparkShader, arguments: [.floatArray("sparks", sparks)],
                vertices: 6, instances: sparks.count / 4 + 1)
        .gesture(
            DragGesture().onChanged { value in
                // Shader space counts pixels; a drag reports points.
                sparks += [Float(value.location.x * scale), Float(value.location.y * scale),
                           Float(28 * scale), Float.random(in: 0...1)]
                if sparks.count > 64 * 4 { sparks.removeFirst(4) }
            }
        )
    }
}
```
