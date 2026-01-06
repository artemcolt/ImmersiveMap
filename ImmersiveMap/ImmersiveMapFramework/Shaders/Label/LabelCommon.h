//
//  LabelCommon.h
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

#include <metal_stdlib>
using namespace metal;

struct ScreenParams {
    float2 viewportSize; // In pixels; used only when outputPixels != 0
    uint outputPixels;   // 0 = NDC, 1 = pixels
};

struct ScreenPointOutput {
    float2 position; // NDC or pixel position, depending on outputPixels
    float depth;     // Clip-space depth (z / w)
    uint visible;    // 0 = clipped/behind, 1 = visible
};

struct LabelCollisionParams {
    uint count;
    float now;
    float duration;
    uint padding;
};
