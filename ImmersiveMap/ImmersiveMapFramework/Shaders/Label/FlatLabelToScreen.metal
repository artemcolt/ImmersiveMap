//
//  FlatLabelToScreen.metal
//  ImmersiveMap
//
//  Created by Artem on 1/2/26.
//

#include <metal_stdlib>
using namespace metal;
#include "../Common.h"
#include "LabelCommon.h"

kernel void flatLabelToScreenKernel(const device LabelInput* inputs [[buffer(0)]],
                                    device ScreenPointOutput* outputs [[buffer(1)]],
                                    constant Camera& camera [[buffer(2)]],
                                    constant ScreenParams& screenParams [[buffer(3)]],
                                    const device float4* tileData [[buffer(4)]],
                                    const device LabelRuntimeState* runtimeStates [[buffer(5)]],
                                    uint gid [[thread_position_in_grid]]) {
    LabelInput input = inputs[gid];
    uint tileIndex = runtimeStates[gid].tileIndex;
    float4 data = tileData[tileIndex];
    float2 tileOrigin = data.xy;
    float tileSize = data.z;

    float2 local = float2(input.uv.x * tileSize, (1.0 - input.uv.y) * tileSize);
    float4 world = float4(tileOrigin + local, 0.0, 1.0);
    float4 clip = camera.matrix * world;

    ScreenPointOutput result;
    if (clip.w <= 0.0) {
        result.position = float2(0.0);
        result.depth = 0.0;
        result.visible = 0;
        outputs[gid] = result;
        return;
    }

    float2 ndc = clip.xy / clip.w;
    float depth = clip.z / clip.w;
    float2 position = ndc;

    if (screenParams.outputPixels != 0 && all(screenParams.viewportSize > 0.0)) {
        position = (ndc * 0.5 + 0.5) * screenParams.viewportSize;
    }

    result.position = position;
    result.depth = depth;
    result.visible = 1;
    outputs[gid] = result;
}
