//
//  TextShader.metal
//  ImmersiveMap
//
//  Created by Artem on 11/2/25.
//

#include <metal_stdlib>
using namespace metal;
#include "Common.h"
#include "Label/RoadLabelCommon.h"

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct LabelVertexIn {
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
    int labelIndex [[attribute(2)]];
};

struct ScreenPointOutput {
    float2 position;
    float depth;
    uint visible;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float alpha;
};

vertex VertexOut textVertex(VertexIn in [[stage_in]],
                            constant float4x4& matrix [[buffer(1)]]
                            ) {
    VertexOut out;
    out.position = matrix * in.position;
    out.uv = in.uv;
    out.alpha = 1.0;
    return out;
}

vertex VertexOut labelTextVertex(LabelVertexIn in [[stage_in]],
                                 constant float4x4& matrix [[buffer(1)]],
                                 const device ScreenPointOutput* screenPositions [[buffer(2)]],
                                 constant int& globalTextShift [[buffer(3)]],
                                 const device TilePointInput* tilePointInputs [[buffer(4)]],
                                 const device uint* collisionVisibility [[buffer(5)]],
                                 const device LabelRuntimeState* labelStates [[buffer(6)]],
                                 constant float& appTime [[buffer(7)]]) {
    VertexOut out;
    int screenIndex = in.labelIndex + globalTextShift;
    ScreenPointOutput screenPoint = screenPositions[screenIndex];
    
    float2 halfSize = tilePointInputs[screenIndex].size * 0.5;
    float2 pixelPosition = screenPoint.position + in.position - halfSize;
    out.position = matrix * float4(pixelPosition, 0.0, 1.0);
    out.uv = in.uv;
    out.alpha = labelStates[screenIndex].state.alpha;
    return out;
}

vertex VertexOut roadLabelTextVertex(LabelVertexIn in [[stage_in]],
                                     constant float4x4& matrix [[buffer(1)]],
                                     const device RoadGlyphPlacementOutput* placements [[buffer(2)]],
                                     const device RoadGlyphInput* glyphInputs [[buffer(3)]],
                                     const device LabelRuntimeState* labelStates [[buffer(4)]]) {
    VertexOut out;
    int glyphIndex = in.labelIndex;
    RoadGlyphPlacementOutput placement = placements[glyphIndex];
    RoadGlyphInput glyphInput = glyphInputs[glyphIndex];
    uint instanceIndex = glyphInput.labelInstanceIndex;

    float2 local = in.position - float2(glyphInput.glyphCenter, 0.0);
    float s = sin(placement.angle);
    float c = cos(placement.angle);
    float2 rotated = float2(local.x * c - local.y * s, local.x * s + local.y * c);
    float2 pixelPosition = placement.position + rotated;

    out.position = matrix * float4(pixelPosition, 0.0, 1.0);
    out.uv = in.uv;
    out.alpha = (placement.visible == 0) ? 0.0 : labelStates[instanceIndex].state.alpha;
    return out;
}

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

fragment float4 textFragment(VertexOut in [[stage_in]],
                             texture2d<float> atlasTexture [[texture(0)]],
                             constant float3& textColor [[buffer(0)]]
                             ) {
    
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);
    float3 msdf = atlasTexture.sample(textureSampler, in.uv).rgb;
    
    float sd = median(msdf.r, msdf.g, msdf.b);
    sd = clamp(sd, 0.0, 1.0);
    float alpha = smoothstep(0.2, 0.6, sd);
    
    float finalAlpha = alpha * in.alpha;
    return float4(finalAlpha * textColor, finalAlpha);
}
