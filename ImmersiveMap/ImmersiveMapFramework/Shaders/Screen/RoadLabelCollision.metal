//
//  RoadLabelCollision.metal
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

#include <metal_stdlib>
using namespace metal;
#include "../Common.h"
#include "ScreenCommon.h"
#include "ScreenCollisionCommon.h"
#include "../Label/RoadLabelCommon.h"

struct RoadLabelCollisionParams {
    uint roadCount;
    uint labelCount;
    uint _padding0;
    uint _padding1;
};

kernel void roadLabelCollisionKernel(const device ScreenPointOutput* roadPoints [[buffer(0)]],
                                     const device ScreenCollisionInput* roadInputs [[buffer(1)]],
                                     const device RoadGlyphInput* roadGlyphInputs [[buffer(2)]],
                                     const device ScreenPointOutput* labelPoints [[buffer(3)]],
                                     const device ScreenCollisionInput* labelInputs [[buffer(4)]],
                                     const device uint* labelVisibility [[buffer(5)]],
                                     device uint* visibility [[buffer(6)]],
                                     constant RoadLabelCollisionParams& params [[buffer(7)]],
                                     uint gid [[thread_position_in_grid]]) {
    if (gid >= params.roadCount) {
        return;
    }

    ScreenPointOutput roadPoint = roadPoints[gid];
    if (roadPoint.visible == 0) {
        visibility[gid] = 0;
        return;
    }

    float2 pos = roadPoint.position;
    ScreenCollisionInput input = roadInputs[gid];
    RoadGlyphInput roadGlyph = roadGlyphInputs[gid];

    for (uint i = 0; i < params.labelCount; i++) {
        if (labelVisibility[i] == 0) {
            continue;
        }

        ScreenPointOutput labelPoint = labelPoints[i];
        if (labelPoint.visible == 0) {
            continue;
        }

        if (screenCollisionIntersects(pos, input, labelPoint.position, labelInputs[i])) {
            visibility[gid] = 0;
            return;
        }
    }

    for (uint i = 0; i < gid; i++) {
        RoadGlyphInput otherGlyph = roadGlyphInputs[i];
        if (otherGlyph.labelInstanceIndex == roadGlyph.labelInstanceIndex) {
            continue;
        }
        if (otherGlyph.pathIndex == roadGlyph.pathIndex) {
            continue;
        }

        ScreenPointOutput otherPoint = roadPoints[i];
        if (otherPoint.visible == 0) {
            continue;
        }

        if (screenCollisionIntersects(pos, input, otherPoint.position, roadInputs[i])) {
            visibility[gid] = 0;
            return;
        }
    }

    visibility[gid] = 1;
}
