//
//  FlatTilePointToScreen.metal
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

kernel void flatTilePointToScreenKernel(const device TilePointInput* inputs [[buffer(0)]],
                                    device ScreenPointOutput* outputs [[buffer(1)]],
                                    constant Camera& camera [[buffer(2)]],
                                    constant ScreenParams& screenParams [[buffer(3)]],
                                    const device float4* tileData [[buffer(4)]],
                                    const device uint* tileIndices [[buffer(5)]],
                                    uint gid [[thread_position_in_grid]]) {
    TilePointInput input = inputs[gid];
    uint tileIndex = tileIndices[gid];
    float4 data = tileData[tileIndex];
    float2 tileOrigin = data.xy;
    float tileSize = data.z;

    float4 clip = flatClipFromTileUV(input.uv, tileOrigin, tileSize, camera);
    ScreenPointOutput result = screenPointFromClip(clip, screenParams);
    outputs[gid] = result;
}
