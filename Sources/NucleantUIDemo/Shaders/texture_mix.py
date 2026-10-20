# Two textures mixed by name, `a` and `b`, wiping from one to the other at
# `blend` — the class input, which the slider changes.
#   pyshaderc texture_mix.py --target compute --texture a --texture b -o texture_mix.spv
class Mix:
    blend: float


def main(uv: float2, m: Mix, a: Texture, b: Texture) -> float4:
    pa = a(uv)
    pb = b(uv)
    edge = smoothstep(m.blend - 0.12, m.blend + 0.12, uv.x)
    return mix(pa, pb, edge)
