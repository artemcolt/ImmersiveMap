//
//  RoadLabelCommon.h
//  ImmersiveMap
//
//  Created by Artem on 2/2/26.
//

#include <metal_stdlib>
using namespace metal;

#ifndef ROAD_LABEL_COMMON
#define ROAD_LABEL_COMMON

struct RoadPathRange {
    uint start;
    uint count;
    uint labelIndex;
    uint anchorSegmentIndex;
    float anchorT;
    float _padding0;
    float _padding1;
    float _padding2;
};

struct RoadGlyphInput {
    uint pathIndex;
    uint instanceIndex;
    uint labelInstanceIndex;
    uint _padding;
    float glyphCenter;
    float labelWidth;
    float spacing;
    float minLength;
};

struct RoadGlyphPlacementOutput {
    float2 position;
    float angle;
    uint visible;
    uint _padding;
};

struct RoadLabelGlyphRange {
    uint start;
    uint count;
    uint _padding0;
    uint _padding1;
};

#endif
