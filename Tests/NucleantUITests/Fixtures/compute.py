# Fixture: a compute module, compiled to compute.spv with
#   pyshaderc compute.py --target compute -o compute.spv
def main(uv: float2) -> float4:
    return float4(uv.x, uv.y, 0.0, 1.0)
