//
//  ScreenCollision.metal
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

#include <metal_stdlib>
using namespace metal;
#include "../Common.h"
#include "ScreenCommon.h"
#include "ScreenCollisionCommon.h"

kernel void screenCollisionKernel(const device ScreenPointOutput* points [[buffer(0)]],
                                  device uint* visibility [[buffer(1)]],
                                  const device ScreenCollisionInput* inputs [[buffer(2)]],
                                  constant ScreenCollisionParams& params [[buffer(3)]],
                                  uint gid [[thread_position_in_grid]]) {
    if (gid >= params.count) {
        return;
    }

    ScreenPointOutput point = points[gid];
    if (point.visible == 0) {
        visibility[gid] = 0;
        return;
    }

    float2 pos = point.position;
    ScreenCollisionInput input = inputs[gid];
    uint isVisible = 1;

    for (uint i = 0; i < gid; i++) {
        ScreenPointOutput other = points[i];
        if (other.visible == 0) {
            continue;
        }

        if (screenCollisionIntersects(pos, input, other.position, inputs[i])) {
            isVisible = 0;
            break;
        }
    }

    visibility[gid] = isVisible;
}
