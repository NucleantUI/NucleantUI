# A sine ripple across the view under the effect.
#   pyshaderc ripple.py --target compute --content-top-down -o ripple.spv
def main(uv: float2, time: float) -> float4:
    p = float2(uv.x + 0.012 * sin(uv.y * 40.0 + time * 3.0), uv.y)
    return layer(p)
