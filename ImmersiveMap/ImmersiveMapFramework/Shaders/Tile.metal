//
//  Tile.metal
//  TucikMap
//
//  Created by Artem on 6/5/25.
//

#include <metal_stdlib>
using namespace metal;
#include "Common.h"

// Add necessary structures for transformation and rendering
struct VertexIn {
    short2 position [[attribute(0)]];
    unsigned char styleIndex [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

struct Style {
    float4 color;
};

vertex VertexOut tileVertexShader(VertexIn vertexIn [[stage_in]],
                                  constant Camera& camera [[buffer(1)]],
                                  constant Style* styles [[buffer(2)]],
                                  constant float4x4& modelMatrix [[buffer(3)]]) {
    
    Style style = styles[vertexIn.styleIndex];
    float4x4 matrix = camera.matrix;
    
    float4 worldPosition = modelMatrix * float4(float2(vertexIn.position.xy), 0.0, 1.0);
    float4 clipPosition = matrix * worldPosition;
    
    VertexOut out;
    out.position = clipPosition;
    out.pointSize = 5.0;
    out.color = style.color;
    return out;
}

fragment float4 tileFragmentShader(VertexOut in [[stage_in]]) {
    return in.color;
}
