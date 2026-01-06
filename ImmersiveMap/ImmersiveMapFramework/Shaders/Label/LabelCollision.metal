//
//  LabelCollision.metal
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

#include <metal_stdlib>
using namespace metal;
#include "../Common.h"
#include "LabelCommon.h"

kernel void labelCollisionKernel(const device ScreenPointOutput* points [[buffer(0)]],
                                 device uint* visibility [[buffer(1)]],
                                 const device GlobeLabelInput* inputs [[buffer(2)]],
                                 device LabelRuntimeState* labelStates [[buffer(3)]],
                                 const device uchar* desiredVisibility [[buffer(4)]],
                                 constant LabelCollisionParams& params [[buffer(5)]],
                                 uint gid [[thread_position_in_grid]]) {
    if (gid >= params.count) {
        return;
    }

    ScreenPointOutput point = points[gid];
    uint isVisible = 1;
    if (point.visible == 0) {
        isVisible = 0;
    }

    float2 pos = point.position;
    float2 halfSize = inputs[gid].size * 0.5;

    for (uint i = 0; i < gid; i++) {
        ScreenPointOutput other = points[i];
        if (other.visible == 0) {
            continue;
        }

        float2 d = abs(pos - other.position);
        float2 otherHalfSize = inputs[i].size * 0.5;
        float2 overlap = halfSize + otherHalfSize;
        if (d.x < overlap.x && d.y < overlap.y) {
            isVisible = 0;
            break;
        }
    }

    if (labelStates[gid].duplicate != 0 || desiredVisibility[gid] == 0) {
        isVisible = 0;
    }
    visibility[gid] = isVisible;

    LabelState state = labelStates[gid].state;
    float desiredTarget = (isVisible != 0) ? 1.0 : 0.0;
    if (desiredTarget != state.target) {
        state.alphaStart = state.alpha;
        state.changeTime = params.now;
        state.target = desiredTarget;
    }

    float t = (params.duration > 0.0) ? ((params.now - state.changeTime) / params.duration) : 1.0;
    t = clamp(t, 0.0, 1.0);
    state.alpha = mix(state.alphaStart, state.target, t);
    labelStates[gid].state = state;
}
