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

struct CometVertexIn {
    float3 startPosition [[attribute(0)]];
    float3 endPosition [[attribute(1)]];
    float size [[attribute(2)]];
    float brightness [[attribute(3)]];
    float startTime [[attribute(4)]];
    float duration [[attribute(5)]];
};

struct CometVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float brightness;
    float2 direction;
    float tailScale;
};

struct CometParams {
    float time;
    float tailScale;
    float radiusScale;
    float fadeOutSeconds;
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

vertex CometVertexOut cometVertexShader(CometVertexIn in [[stage_in]],
                                        constant Camera& camera [[buffer(1)]],
                                        constant CometParams& params [[buffer(2)]]) {
    CometVertexOut out;

    float durationSafe = max(0.01, in.duration);
    float t = (params.time - in.startTime) / durationSafe;
    float fadeOutNorm = params.fadeOutSeconds / durationSafe;
    if (t <= 0.0 || t >= 1.0 + fadeOutNorm) {
        out.position = float4(2.0, 2.0, 0.0, 1.0);
        out.pointSize = 0.0;
        out.brightness = 0.0;
        out.direction = float2(1.0, 0.0);
        return out;
    }

    float tNext = min(1.0, t + 0.02);
    float3 pos = mix(in.startPosition, in.endPosition, t) * params.radiusScale;
    float3 posNext = mix(in.startPosition, in.endPosition, tNext) * params.radiusScale;

    float4 world = float4(pos, 1.0);
    float4 worldNext = float4(posNext, 1.0);

    float4 clip = camera.matrix * world;
    float4 clipNext = camera.matrix * worldNext;
    float2 ndc = clip.xy / max(0.0001, clip.w);
    float2 ndcNext = clipNext.xy / max(0.0001, clipNext.w);
    float2 dir = ndcNext - ndc;
    float dirLen = length(dir);
    out.direction = dirLen > 0.0001 ? (dir / dirLen) : float2(1.0, 0.0);
    out.tailScale = params.tailScale;

    out.position = clip;
    float fadeOut = t > 1.0 ? max(0.0, 1.0 - (t - 1.0) / max(0.01, fadeOutNorm)) : 1.0;
    out.pointSize = in.size;
    out.brightness = in.brightness * fadeOut;
    return out;
}

fragment float4 cometFragmentShader(CometVertexOut in [[stage_in]],
                                    float2 pointCoord [[point_coord]]) {
    float2 p = pointCoord - 0.5;
    float2 dir = normalize(in.direction);
    float2 perp = float2(-dir.y, dir.x);

    float along = dot(p, -dir);
    float across = dot(p, perp);
    float tail = smoothstep(-0.5, 0.5, along);
    float width = exp(-across * across * in.tailScale);
    float alpha = tail * width * in.brightness;
    float3 color = float3(0.85, 0.9, 1.0);
    return float4(color * in.brightness, alpha);
}
