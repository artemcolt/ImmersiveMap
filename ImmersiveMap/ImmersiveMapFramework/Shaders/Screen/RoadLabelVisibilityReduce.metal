//
//  RoadLabelVisibilityReduce.metal
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

#include <metal_stdlib>
using namespace metal;
#include "../Label/RoadLabelCommon.h"

kernel void roadLabelVisibilityReduceKernel(const device uint* glyphVisibility [[buffer(0)]],
                                            const device RoadLabelGlyphRange* ranges [[buffer(1)]],
                                            device uint* instanceVisibility [[buffer(2)]],
                                            constant uint& instanceCount [[buffer(3)]],
                                            uint gid [[thread_position_in_grid]]) {
    if (gid >= instanceCount) {
        return;
    }

    RoadLabelGlyphRange range = ranges[gid];
    if (range.count == 0) {
        instanceVisibility[gid] = 0;
        return;
    }

    uint visible = 1;
    uint end = range.start + range.count;
    for (uint i = range.start; i < end; i++) {
        if (glyphVisibility[i] == 0) {
            visible = 0;
            break;
        }
    }
    instanceVisibility[gid] = visible;
}
