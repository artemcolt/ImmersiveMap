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

static inline bool rectRectCollision(float2 aPos, float2 aHalf, float2 bPos, float2 bHalf) {
    float2 d = abs(aPos - bPos);
    float2 overlap = aHalf + bHalf;
    return (d.x < overlap.x) && (d.y < overlap.y);
}

static inline bool circleCircleCollision(float2 aPos, float aRadius, float2 bPos, float bRadius) {
    float2 d = aPos - bPos;
    float r = aRadius + bRadius;
    return dot(d, d) < r * r;
}

static inline bool rectCircleCollision(float2 rectPos, float2 rectHalf, float2 circlePos, float circleRadius) {
    float2 delta = abs(circlePos - rectPos) - rectHalf;
    float2 clamped = max(delta, float2(0.0));
    return dot(clamped, clamped) < circleRadius * circleRadius;
}

static inline bool screenCollisionIntersects(float2 aPos,
                                             ScreenCollisionInput aInput,
                                             float2 bPos,
                                             ScreenCollisionInput bInput) {
    if (aInput.shapeType == ScreenCollisionShapeRect && bInput.shapeType == ScreenCollisionShapeRect) {
        return rectRectCollision(aPos, aInput.halfSize, bPos, bInput.halfSize);
    }
    if (aInput.shapeType == ScreenCollisionShapeCircle && bInput.shapeType == ScreenCollisionShapeCircle) {
        return circleCircleCollision(aPos, aInput.radius, bPos, bInput.radius);
    }
    if (aInput.shapeType == ScreenCollisionShapeRect && bInput.shapeType == ScreenCollisionShapeCircle) {
        return rectCircleCollision(aPos, aInput.halfSize, bPos, bInput.radius);
    }
    if (aInput.shapeType == ScreenCollisionShapeCircle && bInput.shapeType == ScreenCollisionShapeRect) {
        return rectCircleCollision(bPos, bInput.halfSize, aPos, aInput.radius);
    }
    return false;
}

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
