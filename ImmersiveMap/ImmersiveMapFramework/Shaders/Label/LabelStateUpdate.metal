//
//  LabelStateUpdate.metal
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

#include <metal_stdlib>
using namespace metal;
#include "../Common.h"

struct LabelStateUpdateParams {
    uint count;
    float now;
    float duration;
    uint _padding;
};

kernel void labelStateUpdateKernel(const device uint* visibility [[buffer(0)]],
                                   device LabelRuntimeState* labelStates [[buffer(1)]],
                                   constant LabelStateUpdateParams& params [[buffer(2)]],
                                   uint gid [[thread_position_in_grid]]) {
    if (gid >= params.count) {
        return;
    }

    LabelRuntimeState runtimeState = labelStates[gid];
    LabelState state = runtimeState.state;
    uint isVisible = (visibility[gid] != 0 && runtimeState.isRetained == 0) ? 1 : 0;

    float target = (isVisible != 0) ? 1.0 : 0.0;
    if (target != state.target) {
        state.alphaStart = state.alpha;
        state.changeTime = params.now;
        state.target = target;
    }

    float t = (params.duration > 0.0) ? ((params.now - state.changeTime) / params.duration) : 1.0;
    t = clamp(t, 0.0, 1.0);
    state.alpha = mix(state.alphaStart, state.target, t);
    if (runtimeState.duplicate == 1) {
        state.alpha = 0.0;
    }

    labelStates[gid].state = state;
}
