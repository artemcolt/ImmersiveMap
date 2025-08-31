//
//  Shaders.metal
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut vertexShader(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = in.position;
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]]) {
    return float4(1.0, 0.0, 0.0, 1.0); // Красный цвет (RGBA)
}
