//
//  ScreenPointDebug.metal
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

#include <metal_stdlib>
using namespace metal;
#include "ScreenCommon.h"

struct DebugVertexOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]];
};

vertex DebugVertexOut screenPointDebugVertex(uint vid [[vertex_id]],
                                             const device ScreenPointOutput* points [[buffer(0)]],
                                             constant float4x4& matrix [[buffer(1)]],
                                             constant float4& color [[buffer(2)]]) {
    ScreenPointOutput point = points[vid];

    DebugVertexOut out;
    out.color = color;
    out.pointSize = (point.visible == 0) ? 0.0 : 6.0;
    if (point.visible == 0) {
        out.position = float4(-2.0, -2.0, 0.0, 1.0);
        return out;
    }

    out.position = matrix * float4(point.position, 0.0, 1.0);
    return out;
}

fragment float4 screenPointDebugFragment(DebugVertexOut in [[stage_in]]) {
    return in.color;
}
