//
//  Starfield.metal
//  ImmersiveMap
//
//  Created by Artem on 9/21/25.
//

#include <metal_stdlib>
using namespace metal;
#include "Common.h"

struct StarVertexIn {
    float3 position [[attribute(0)]];
    float size [[attribute(1)]];
    float brightness [[attribute(2)]];
};

struct StarVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float brightness;
};

struct StarfieldParams {
    float radiusScale;
    float3 padding;
};

vertex StarVertexOut starfieldVertexShader(StarVertexIn in [[stage_in]],
                                           constant Camera& camera [[buffer(1)]],
                                           constant Globe& globe [[buffer(2)]],
                                           constant StarfieldParams& params [[buffer(3)]]) {
    StarVertexOut out;
    float maxLatitude = 2.0 * atan(exp(M_PI_F)) - M_PI_2_F;
    float latitude = globe.panY * maxLatitude;
    float longitude = globe.panX * M_PI_F;

    float cx = cos(-latitude);
    float sx = sin(-latitude);
    float cy = cos(-longitude);
    float sy = sin(-longitude);

    float4x4 rotation = float4x4(
        float4(cy,        0,         -sy,       0),
        float4(sy * sx,   cx,        cy * sx,   0),
        float4(sy * cx,  -sx,        cy * cx,   0),
        float4(0,         0,          0,        1)
    );

    float starRadius = globe.radius * params.radiusScale;
    float4 world = float4(in.position * starRadius, 1.0) * rotation * translationMatrix(float3(0, 0, -globe.radius));
    out.position = camera.matrix * world;
    float sizeScale = starRadius / globe.radius;
    out.pointSize = in.size * sizeScale * 0.25;
    out.brightness = in.brightness;
    return out;
}

fragment float4 starfieldFragmentShader(StarVertexOut in [[stage_in]],
                                        float2 pointCoord [[point_coord]],
                                        constant float &time [[buffer(0)]]) {
    float twinkle = 0.85 + 0.15 * sin(time * 1.7 + in.brightness * 40.0);
    float intensity = in.brightness * twinkle;
    float3 color = float3(0.9, 0.95, 1.0);
    return float4(color * intensity, intensity);
}
