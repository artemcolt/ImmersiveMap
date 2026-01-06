//
//  GlobeLabelToScreen.metal
//  ImmersiveMap
//
//  Created by Artem on 1/2/26.
//

#include <metal_stdlib>
using namespace metal;
#include "../Common.h"
#include "LabelCommon.h"


float4 globeClipFromTileUV(float2 localUv,
                           int3 tile,
                           constant Camera& camera,
                           constant Globe& globe,
                           thread float3& horizonPositionWorld) {
    float vertexUvX = localUv.x; // 0..1 inside the tile
    float vertexUvY = localUv.y; // 0..1 inside the tile

    int tileX = tile.x;
    int tileY = tile.y;
    int tileZ = tile.z;

    float zPow = pow(2.0, tileZ);
    float size = 1.0 / zPow;

    vertexUvX = vertexUvX / zPow + size * tileX;

    float mercatorV = (float(tileY) + vertexUvY) / zPow;
    float latitudeAtUv = atan(sinh(M_PI_F * (1.0 - 2.0 * mercatorV)));
    vertexUvY = 1.0 - (latitudeAtUv + M_PI_2_F) / M_PI_F;

    float globePanX = globe.panX;
    float globePanY = globe.panY;
    float transition = globe.transition;

    float maxLatitude = 2.0 * atan(exp(M_PI_F)) - M_PI_2_F;
    float latitude = globePanY * maxLatitude;
    float longitude = globePanX * M_PI_F;

    float distortion = cos(latitude);
    float mapSizeScale = mix(distortion, 1.0, transition);

    float globeRadius = globe.radius;
    float mapSize = 2 * M_PI_F * globeRadius * mapSizeScale;

    float phi = latitudeAtUv - M_PI_2_F;
    float theta = 2 * M_PI_F * vertexUvX;

    float x = globeRadius * sin(phi) * sin(theta);
    float y = globeRadius * cos(phi);
    float z = globeRadius * sin(phi) * cos(theta);
    float3 spherePosition = float3(x, y, z);

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

    float panY_merc_norm = getYMercNorm(latitude);

    float halfMapSize = mapSize / 2.0;
    float posUvX = wrap(vertexUvX * mapSize - halfMapSize + globePanX * halfMapSize, mapSize);

    float lat_v = M_PI_F * vertexUvY - M_PI_2_F;      // [-pi/2..pi/2]
    float v_merc_norm = -getYMercNorm(lat_v);         // [-1..1]
    float posUvY = (v_merc_norm - panY_merc_norm) * halfMapSize;

    float4 rotatedPosition = float4(spherePosition, 1.0) * rotation;

    float4x4 translationM = translationMatrix(float3(0, 0, -globeRadius));
    float4 spherePositionTranslated = rotatedPosition * translationM;
    float4 flatPosition = float4(posUvX, posUvY, 0, 1.0);
    float4 position = mix(spherePositionTranslated, flatPosition, transition);
    horizonPositionWorld = position.xyz;
    return camera.matrix * position;
}

kernel void globeLabelToScreenKernel(const device LabelInput* inputs [[buffer(0)]],
                                     device ScreenPointOutput* outputs [[buffer(1)]],
                                     constant Camera& camera [[buffer(2)]],
                                     constant Globe& globe [[buffer(3)]],
                                     constant ScreenParams& screenParams [[buffer(4)]],
                                     uint gid [[thread_position_in_grid]]) {
    LabelInput input = inputs[gid];
    float3 horizonPositionWorld = float3(0.0);
    float4 clip = globeClipFromTileUV(input.uv, input.tile, camera, globe, horizonPositionWorld);

    ScreenPointOutput result;
    if (clip.w <= 0.0) {
        result.position = float2(0.0);
        result.depth = 0.0;
        result.visible = 0;
        outputs[gid] = result;
        return;
    }

    bool horizonHidden = false;
    float3 globeCenter = float3(0.0, 0.0, -globe.radius);
    float3 toCamera = camera.eye - globeCenter;
    float toCameraLen = length(toCamera);
    if (toCameraLen > 0.0) {
        if (globe.transition < 0.95) {
            float dotToCamera = dot(horizonPositionWorld - globeCenter, toCamera);
            float horizonFade = smoothstep(0.8, 0.95, globe.transition);
            float horizonThreshold = mix(globe.radius * globe.radius, -1e6, horizonFade);
            if (dotToCamera < horizonThreshold) {
                horizonHidden = true;
            }
        }
    }

    float2 ndc = clip.xy / clip.w; // [-1..1]
    float depth = clip.z / clip.w;
    float2 position = ndc;

    if (screenParams.outputPixels != 0 && all(screenParams.viewportSize > 0.0)) {
        position = (ndc * 0.5 + 0.5) * screenParams.viewportSize;
    }

    result.position = position;
    result.depth = depth;
    result.visible = horizonHidden ? 0 : 1;
    outputs[gid] = result;
}
