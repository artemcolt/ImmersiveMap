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
                                 const device LabelInput* inputs [[buffer(2)]],
                                 device LabelRuntimeState* labelStates [[buffer(3)]],
                                 constant LabelCollisionParams& params [[buffer(4)]],
                                 uint gid [[thread_position_in_grid]]) {
    if (gid >= params.count) {
        return;
    }
    
    LabelRuntimeState runtimeState = labelStates[gid];
    LabelState state = runtimeState.state;
    uint isVisible = runtimeState.isRetained == 0.0;

    ScreenPointOutput point = points[gid];
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

    visibility[gid] = isVisible;

    float target = (isVisible != 0) ? 1.0 : 0.0;
    if (target != state.target) {
        state.alphaStart = state.alpha;
        state.changeTime = params.now;
        state.target = target;
    }

    float t = (params.duration > 0.0) ? ((params.now - state.changeTime) / params.duration) : 1.0;
    t = clamp(t, 0.0, 1.0);
    state.alpha = mix(state.alphaStart, state.target, t);
    if (runtimeState.duplicate == 1.0) {
        state.alpha = 0.0;
    }
    
    labelStates[gid].state = state;
}
