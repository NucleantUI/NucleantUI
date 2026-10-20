# An animated backdrop: bands of light drifting between two colours.
#
# `look` is the app's `Look` model, read whole: the Swift side packs the same
# fields in the same order, and PyShader lays them out the way the GPU reads
# a buffer (std430) — colours at 0 and 16, then the three numbers.

class Look:
    color_a: float4
    color_b: float4
    intensity: float
    speed: float
    scale: float


def main(uv: float2, time: float, resolution: float2, look: Look) -> float4:
    aspect = resolution.x / resolution.y
    p = (uv - 0.5) * float2(aspect, 1.0) * look.scale
    t = time * look.speed
    v = sin(p.x * 3.0 + t) + sin(p.y * 4.0 - t * 1.3) + sin((p.x + p.y) * 2.5 + t * 0.7)
    band = 0.5 + 0.5 * sin(v * 1.5)
    glow = smoothstep(1.2, 0.0, length(p) / look.scale)
    color = mix(look.color_a.xyz, look.color_b.xyz, band) * look.intensity * (0.35 + 0.65 * glow)
    return float4(color, 1.0)
