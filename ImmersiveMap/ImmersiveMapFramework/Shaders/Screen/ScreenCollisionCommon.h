//
//  ScreenCollisionCommon.h
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

#include <metal_stdlib>
using namespace metal;

#ifndef SCREEN_COLLISION_COMMON
#define SCREEN_COLLISION_COMMON

enum ScreenCollisionShapeType {
    ScreenCollisionShapeRect = 0,
    ScreenCollisionShapeCircle = 1
};

struct ScreenCollisionInput {
    float2 halfSize; // Rect half-size in pixels
    float radius;    // Circle radius in pixels
    uint shapeType;  // ScreenCollisionShapeType
};

struct ScreenCollisionParams {
    uint count;
    uint _padding0;
    uint _padding1;
    uint _padding2;
};

#endif
