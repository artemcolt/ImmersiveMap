//
//  TextShader.metal
//  ImmersiveMapFramework
//  Created by Artem on 11/2/25.
//

#include <metal_stdlib>
using namespace metal;
#include "Shared/LabelTextCommon.h"

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct TextStyle {
    float3 textColor;
    float _padding0;
    float3 strokeColor;
    float strokeWidthPx;
};

vertex VertexOut textVertex(VertexIn in [[stage_in]],
                            constant float4x4& matrix [[buffer(1)]]
                            ) {
    VertexOut out;
    out.position = matrix * in.position;
    out.uv = in.uv;
    out.alpha = 1.0;
    out.spriteUV = float2(0.0);
    return out;
}

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

static float computeScreenPxDist(VertexOut in,
                                 texture2d<float> atlasTexture) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float3 msdf = atlasTexture.sample(textureSampler, in.uv).rgb;
    float sd = median(msdf.r, msdf.g, msdf.b) - 0.5;
    const float distanceRange = 8.0;
    float2 texSize = float2(atlasTexture.get_width(), atlasTexture.get_height());
    float2 unitRange = float2(distanceRange) / texSize;
    float2 duv = max(fwidth(in.uv), float2(1e-6));
    float2 screenTexSize = 1.0 / duv;
    float screenPxRange = max(0.5 * dot(unitRange, screenTexSize), 1.0);
    return sd * screenPxRange;
}

fragment float4 textFragment(VertexOut in [[stage_in]],
                             texture2d<float> atlasTexture [[texture(0)]],
                             constant TextStyle& style [[buffer(0)]]
                             ) {
    float screenPxDist = computeScreenPxDist(in, atlasTexture);

    const float boldBiasPx = 0.75;
    float fill = smoothstep(-0.5, 0.5, screenPxDist + boldBiasPx);
    float2 texSize = float2(atlasTexture.get_width(), atlasTexture.get_height());
    float2 unitRange = float2(8.0) / texSize;
    float2 duv = max(fwidth(in.uv), float2(1e-6));
    float2 screenTexSize = 1.0 / duv;
    float screenPxRange = max(0.5 * dot(unitRange, screenTexSize), 1.0);
    float maxStrokePx = max(0.5 * screenPxRange - 0.5, 0.0);
    float strokeWidthPx = min(style.strokeWidthPx, maxStrokePx);
    float outer = smoothstep(-strokeWidthPx - 0.5, -strokeWidthPx + 0.5, screenPxDist);
    float stroke = clamp(outer - fill, 0.0, 1.0);

    float coverage = clamp(fill + stroke, 0.0, 1.0);
    float alpha = coverage * in.alpha;
    float3 color = (fill * style.textColor + stroke * style.strokeColor) / max(coverage, 1e-5);
    return float4(color, alpha);
}

fragment float4 roadTextFragment(VertexOut in [[stage_in]],
                                 texture2d<float> atlasTexture [[texture(0)]],
                                 constant TextStyle& style [[buffer(0)]]
                                 ) {
    float screenPxDist = computeScreenPxDist(in, atlasTexture);

    const float fillBiasPx = 0.75;
    float fill = smoothstep(-0.5, 0.5, screenPxDist + fillBiasPx);

    float2 texSize = float2(atlasTexture.get_width(), atlasTexture.get_height());
    float2 unitRange = float2(8.0) / texSize;
    float2 duv = max(fwidth(in.uv), float2(1e-6));
    float2 screenTexSize = 1.0 / duv;
    float screenPxRange = max(0.5 * dot(unitRange, screenTexSize), 1.0);

    // Road labels need a less aggressive clamp than point labels: the generic
    // half-range cap can collapse the outline to zero on rotated thin glyphs.
    // Keep a small guaranteed stroke, but stay within the signed-distance support.
    float maxStrokePx = max(screenPxRange - 0.75, 0.75);
    float strokeWidthPx = min(style.strokeWidthPx, maxStrokePx);
    float outer = smoothstep(-strokeWidthPx - 0.5, -strokeWidthPx + 0.5, screenPxDist);
    float stroke = clamp(outer - fill, 0.0, 1.0);

    float coverage = clamp(fill + stroke, 0.0, 1.0);
    float alpha = coverage * in.alpha;
    float3 color = (fill * style.textColor + stroke * style.strokeColor) / max(coverage, 1e-5);
    return float4(color, alpha);
}
