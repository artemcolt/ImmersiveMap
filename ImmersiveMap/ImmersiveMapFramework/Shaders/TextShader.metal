//
//  TextShader.metal
//  ImmersiveMap
//
//  Created by Artem on 11/2/25.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut textVertex(VertexIn in [[stage_in]],
                            constant float4x4& matrix [[buffer(1)]]
                            ) {
    VertexOut out;
    out.position = matrix * in.position;
    out.uv = in.uv;
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
    //return float4(float3(sd), 1.0);
    float alpha = smoothstep(0.2, 0.6, sd);
    
    return float4(alpha * textColor, alpha);
}
