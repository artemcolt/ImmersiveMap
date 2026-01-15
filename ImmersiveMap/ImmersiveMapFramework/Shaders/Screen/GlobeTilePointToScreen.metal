//
//  GlobeTilePointToScreen.metal
//  ImmersiveMap
//
//  Created by Artem on 1/2/26.
//

#include <metal_stdlib>
using namespace metal;
#include "../Common.h"
#include "../Screen/ScreenCommon.h"
#include "../Screen/ScreenPoint.h"
#include "../TilePointCommon.h"


kernel void globeTilePointToScreenKernel(const device TilePointInput* inputs [[buffer(0)]],
                                     device ScreenPointOutput* outputs [[buffer(1)]],
                                     constant Camera& camera [[buffer(2)]],
                                     constant Globe& globe [[buffer(3)]],
                                     constant ScreenParams& screenParams [[buffer(4)]],
                                     uint gid [[thread_position_in_grid]]) {
    TilePointInput input = inputs[gid];
    float3 horizonPositionWorld = float3(0.0);
    float4 clip = globeClipFromTileUV(input.uv, input.tile, camera, globe, horizonPositionWorld);

    ScreenPointOutput result = screenPointFromClip(clip, screenParams);
    if (result.visible == 0) {
        outputs[gid] = result;
        return;
    }

    bool horizonHidden = false;
    float3 globeCenter = float3(0.0, 0.0, -globe.radius);
    float3 toCamera = camera.eye - globeCenter;
    float toCameraLen = length(toCamera);
    if (toCameraLen > 0.0) {
        if (globe.transition < 0.95) {
            float dotToCamera = dot(horizonPositionWorld - globeCenter, toCamera);
            float horizonFade = smoothstep(0.8, 0.95, globe.transition);
            float horizonThreshold = mix(globe.radius * globe.radius, -1e6, horizonFade);
            if (dotToCamera < horizonThreshold) {
                horizonHidden = true;
            }
        }
    }

    result.visible = horizonHidden ? 0 : result.visible;
    outputs[gid] = result;
}
