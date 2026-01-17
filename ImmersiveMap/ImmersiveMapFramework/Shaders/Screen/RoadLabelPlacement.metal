//
//  RoadLabelPlacement.metal
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

#include <metal_stdlib>
using namespace metal;
#include "../Common.h"
#include "ScreenCommon.h"
#include "../Label/RoadLabelCommon.h"

kernel void roadLabelPlacementKernel(const device ScreenPointOutput* pathPoints [[buffer(0)]],
                                     const device RoadPathRange* pathRanges [[buffer(1)]],
                                     const device RoadLabelAnchor* anchors [[buffer(2)]],
                                     const device RoadGlyphInput* glyphInputs [[buffer(3)]],
                                     device RoadGlyphPlacementOutput* placements [[buffer(4)]],
                                     device ScreenPointOutput* screenPoints [[buffer(5)]],
                                     constant uint& glyphCount [[buffer(6)]],
                                     uint gid [[thread_position_in_grid]]) {
    if (gid >= glyphCount) {
        return;
    }

    RoadGlyphInput input = glyphInputs[gid];
    RoadPathRange pathRange = pathRanges[input.pathIndex];
    RoadLabelAnchor anchor = anchors[input.labelInstanceIndex];

    RoadGlyphPlacementOutput placement;
    placement.position = float2(0.0);
    placement.angle = 0.0;
    placement.visible = 0;

    ScreenPointOutput screenPoint;
    screenPoint.position = float2(0.0);
    screenPoint.depth = 0.0;
    screenPoint.visible = 0;

    if (pathRange.count < 2) {
        placements[gid] = placement;
        screenPoints[gid] = screenPoint;
        return;
    }

    float totalLength = 0.0;
    float anchorDistance = -1.0;
    bool hasInvisible = false;
    uint start = pathRange.start;
    uint end = start + pathRange.count;
    uint anchorSegmentIndex = min(anchor.segmentIndex, pathRange.count - 2);
    float anchorT = clamp(anchor.t, 0.0, 1.0);
    float2 prev = pathPoints[start].position;
    if (pathPoints[start].visible == 0) {
        hasInvisible = true;
    }

    for (uint i = start + 1; i < end; i++) {
        ScreenPointOutput point = pathPoints[i];
        if (point.visible == 0) {
            hasInvisible = true;
        }
        float2 current = point.position;
        float segmentLength = length(current - prev);
        uint segmentIndex = i - start - 1;
        if (segmentIndex == anchorSegmentIndex) {
            anchorDistance = totalLength + segmentLength * anchorT;
        }
        totalLength += segmentLength;
        prev = current;
    }

    if (hasInvisible || totalLength < input.minLength) {
        placements[gid] = placement;
        screenPoints[gid] = screenPoint;
        return;
    }

    float minCenterSpacing = max(1.0, input.labelWidth + input.spacing);
    float usableLength = max(0.0, totalLength - input.labelWidth);
    uint maxInstances = (uint)(floor(usableLength / minCenterSpacing)) + 1;
    if (input.instanceIndex >= maxInstances) {
        placements[gid] = placement;
        screenPoints[gid] = screenPoint;
        return;
    }

    if (anchorDistance < 0.0) {
        anchorDistance = totalLength * 0.5;
    }

    float baseDistance = anchorDistance;

    float2 startPos = pathPoints[start].position;
    float2 endPos = pathPoints[end - 1].position;
    float2 overall = endPos - startPos;
    bool reverse = false;
    if (length(overall) > 0.0) {
        float overallAngle = atan2(overall.y, overall.x);
        reverse = (overallAngle > M_PI_2_F || overallAngle < -M_PI_2_F);
    }

    float glyphOffset = input.glyphCenter - input.labelWidth * 0.5;
    if (reverse) {
        glyphOffset = -glyphOffset;
    }
    float targetDistance = baseDistance + glyphOffset;
    if (targetDistance < 0.0 || targetDistance > totalLength) {
        placements[gid] = placement;
        screenPoints[gid] = screenPoint;
        return;
    }

    float accumulated = 0.0;
    float2 p0 = pathPoints[start].position;
    for (uint i = start + 1; i < end; i++) {
        float2 p1 = pathPoints[i].position;
        float segmentLength = length(p1 - p0);
        if (segmentLength > 0.0) {
            if (accumulated + segmentLength >= targetDistance) {
                float t = (targetDistance - accumulated) / segmentLength;
                float2 position = mix(p0, p1, t);
                float2 dir = normalize(p1 - p0);
                float angle = atan2(dir.y, dir.x);
                if (reverse) {
                    angle += M_PI_F;
                    dir = -dir;
                }

                placement.position = position;
                placement.angle = angle;
                placement.visible = 1;

                screenPoint.position = position;
                screenPoint.depth = 0.0;
                screenPoint.visible = 1;
                break;
            }
            accumulated += segmentLength;
        }
        p0 = p1;
    }

    placements[gid] = placement;
    screenPoints[gid] = screenPoint;
}
