# One quad over the view, its fragment stage a lens bulging the middle and
# darkening the edges.
#   pyshaderc lens.py --target graphics --content -o lens.spv
QUAD = [float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)]


class Quad:
    position: float4
    local: float2


def vertex(vertex_index: int) -> Quad:
    quad = QUAD
    corner = quad[vertex_index]
    return Quad(position=float4(corner, 0.0, 1.0), local=corner * 0.5 + 0.5)


def fragment(local: float2, time: float) -> float4:
    d = local - float2(0.5, 0.5)
    r = length(d)
    pull = 0.3 * (1.0 - smoothstep(0.0, 0.5, r)) * (0.75 + 0.25 * sin(time * 2.0))
    colour = layer(float2(0.5, 0.5) + d * (1.0 - pull))
    vignette = smoothstep(0.8, 0.35, r)
    return float4(colour.xyz * vignette, colour.w)
