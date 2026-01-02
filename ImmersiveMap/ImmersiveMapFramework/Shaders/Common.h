//
//  Common.h
//  ImmersiveMap
//
//  Created by Artem on 9/4/25.
//

#include <metal_stdlib>
using namespace metal;

#ifndef COMMON
#define COMMON

struct Camera {
    float4x4 matrix;
};

struct Globe {
    float panX;
    float panY;
    float radius;
    float transition;
};

float wrap(float x, float size);

float4x4 rotationMatrix(float3 axis, float angle);

float4x4 translationMatrix(float3 t);

float getYMercNorm(float latitude);

#endif
