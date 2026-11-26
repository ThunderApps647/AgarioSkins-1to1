#include <metal_stdlib>
using namespace metal;

struct GridUniforms {
    float2 viewportSize;
    float2 cameraPos;
    float zoom;
    float cellSize;
    float gridGray;
    float lineWidthPx;
    float4 bgColor;
};

struct BoundaryUniforms {
    float2 viewportSize;
    float2 cameraPos;
    float2 arenaMin;
    float2 arenaMax;
    float zoom;
    float fadeWidth;
    float minAlpha;
    float borderLineWidth;
    float easePower;
    int blendMode;
    float2 _pad;
    float4 fillColor;
    float4 lineColor;
};

struct QuadOut {
    float4 position [[position]];
    float2 pixelPos;
};

vertex QuadOut fullscreen_vertex(uint vid [[vertex_id]],
                                 constant float2 &viewportSize [[buffer(0)]]) {
    const float2 pos[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    QuadOut out;
    out.position = float4(pos[vid], 0.0, 1.0);
    // Top-left origin pixel coordinates matching SwiftUI / UIKit screen space
    float2 uv = float2((pos[vid].x + 1.0) * 0.5, (1.0 - pos[vid].y) * 0.5);
    out.pixelPos = uv * viewportSize;
    return out;
}

// OptimizedArenaBackground::draw (0x10030e108)
fragment float4 grid_fragment(QuadOut in [[stage_in]],
                              constant GridUniforms &u [[buffer(0)]]) {
    float2 worldPos = u.cameraPos + (in.pixelPos - u.viewportSize * 0.5) / u.zoom;
    float2 cellCoord = worldPos / u.cellSize;
    float2 distToGrid = abs(fract(cellCoord + 0.5) - 0.5) * u.cellSize * u.zoom;
    float d = min(distToGrid.x, distToGrid.y);
    float halfW = max(0.35, u.lineWidthPx * 0.5);
    float coverage = 1.0 - smoothstep(max(0.0, halfW - 0.5), halfW + 0.5, d);
    float3 rgb = mix(u.bgColor.rgb, float3(u.gridGray), coverage);
    return float4(rgb, 1.0);
}

// ArenaBoundaryShaderEffect (0x102304083)
fragment float4 boundary_fragment(QuadOut in [[stage_in]],
                                  constant BoundaryUniforms &u [[buffer(0)]]) {
    float2 worldPos = u.cameraPos + (in.pixelPos - u.viewportSize * 0.5) / u.zoom;
    float inside = step(u.arenaMin.x, worldPos.x) * step(u.arenaMin.y, worldPos.y)
                 * step(worldPos.x, u.arenaMax.x) * step(worldPos.y, u.arenaMax.y);
    if (inside > 0.5) {
        discard_fragment();
    }
    float dx = 0.0;
    if (worldPos.x < u.arenaMin.x) { dx = u.arenaMin.x - worldPos.x; }
    else if (worldPos.x > u.arenaMax.x) { dx = worldPos.x - u.arenaMax.x; }

    float dy = 0.0;
    if (worldPos.y < u.arenaMin.y) { dy = u.arenaMin.y - worldPos.y; }
    else if (worldPos.y > u.arenaMax.y) { dy = worldPos.y - u.arenaMax.y; }

    float distSquared = dx * dx + dy * dy;
    float borderLineWidthSquared = u.borderLineWidth * u.borderLineWidth;
    if (distSquared < borderLineWidthSquared) {
        return u.lineColor;
    }

    distSquared = distSquared - borderLineWidthSquared;
    float fadeWidthSquared = max(1.0, u.fadeWidth * u.fadeWidth);
    float t = clamp(distSquared / fadeWidthSquared, 0.0, 1.0);
    float tEase = 1.0 - pow(max(0.0, 1.0 - t), u.easePower);
    float strength = 1.0 - tEase;
    float alphaFactor = mix(1.0, u.minAlpha, tEase);

    if (u.blendMode == 0) {
        return float4(u.fillColor.rgb, u.fillColor.a * alphaFactor);
    } else if (u.blendMode == 1) {
        float3 minMultiplier = mix(float3(1.0), u.fillColor.rgb, u.minAlpha);
        float3 multiplier = mix(minMultiplier, u.fillColor.rgb, strength);
        return float4(multiplier, 1.0);
    } else {
        float3 addColor = u.fillColor.rgb * strength;
        return float4(addColor, u.fillColor.a * alphaFactor);
    }
}

struct SolidVertexIn {
    float2 pixelPos;
    float4 color;
};

struct SolidOut {
    float4 position [[position]];
    float4 color;
};

vertex SolidOut cell_solid_vertex(const device SolidVertexIn *verts [[buffer(0)]],
                                  constant float2 &viewportSize [[buffer(1)]],
                                  uint vid [[vertex_id]]) {
    SolidOut out;
    float2 p = verts[vid].pixelPos;
    float ndcX = (p.x / viewportSize.x) * 2.0 - 1.0;
    float ndcY = 1.0 - (p.y / viewportSize.y) * 2.0;
    out.position = float4(ndcX, ndcY, 0.0, 1.0);
    out.color = verts[vid].color;
    return out;
}

fragment float4 cell_solid_fragment(SolidOut in [[stage_in]]) {
    return in.color;
}

struct TexVertexIn {
    float2 pixelPos;
    float2 texCoord;
    float4 tint;
};

struct TexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 tint;
};

vertex TexOut cell_tex_vertex(const device TexVertexIn *verts [[buffer(0)]],
                              constant float2 &viewportSize [[buffer(1)]],
                              uint vid [[vertex_id]]) {
    TexOut out;
    float2 p = verts[vid].pixelPos;
    float ndcX = (p.x / viewportSize.x) * 2.0 - 1.0;
    float ndcY = 1.0 - (p.y / viewportSize.y) * 2.0;
    out.position = float4(ndcX, ndcY, 0.0, 1.0);
    out.texCoord = verts[vid].texCoord;
    out.tint = verts[vid].tint;
    return out;
}

fragment float4 cell_tex_fragment(TexOut in [[stage_in]],
                                  texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.texCoord) * in.tint;
    if (c.a <= 0.002) {
        discard_fragment();
    }
    return c;
}
