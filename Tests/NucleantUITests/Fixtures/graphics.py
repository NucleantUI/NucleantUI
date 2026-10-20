# Fixture: a vertex + fragment module, compiled to graphics.spv with
#   pyshaderc graphics.py --target graphics -o graphics.spv
class V:
    position: float4
    uv: float2


def vertex(vertex_index: int) -> V:
    corner = float2(float((vertex_index << 1) & 2), float(vertex_index & 2))
    return V(position=float4(corner * 2.0 - 1.0, 0.0, 1.0), uv=corner)


def fragment(uv: float2) -> float4:
    return float4(uv.x, uv.y, 0.0, 1.0)
