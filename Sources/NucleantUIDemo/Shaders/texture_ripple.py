# An effect over a texture: `layer(uv)` is the texture, as it is the view
# under `.shader(_:)`.
#   pyshaderc texture_ripple.py --target compute --content -o texture_ripple.spv
def main(uv: float2, time: float) -> float4:
    wave = sin(uv.y * 26.0 + time * 2.0) * 0.012
    return layer(float2(uv.x + wave, uv.y))
