// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  RenderUniforms.h
//  ImmersiveMap
//

#include <metal_stdlib>
using namespace metal;

#ifndef RENDER_UNIFORMS
#define RENDER_UNIFORMS

struct Camera {
    float4x4 matrix;
    float3 eye;
    float _padding;
};

struct Globe {
    float panX;
    float panY;
    float radius;
    float transition;
};

struct EarthScene {
    float3 sunDirection;
    uint isEnabled;
    float daySideMinimumBrightness;
    float nightSideBrightness;
    float terminatorFadeWidth;
    float nightLightsIntensity;
    float nightLightsTerminatorFadeWidth;
    uint nightLightsEnabled;
    uint sunVisualEnabled;
    float sunDiskAngularSize;
    float sunDiskIntensity;
    float sunGlowIntensity;
    float sunEdgeGlareIntensity;
    float sunLimbHaloIntensity;
    float sunLimbHaloWidth;
    uint2 _padding0;
};

#endif
