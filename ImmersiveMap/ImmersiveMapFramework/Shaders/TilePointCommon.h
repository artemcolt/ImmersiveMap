//
//  TilePointCommon.h
//  ImmersiveMap
//
//  Created by Artem on 1/10/26.
//

#include <metal_stdlib>
using namespace metal;
#include "Common.h"

#ifndef TILE_POINT_COMMON
#define TILE_POINT_COMMON

static inline float4 flatClipFromTileUV(float2 tileUv,
                                        float2 tileOrigin,
                                        float tileSize,
                                        constant Camera& camera) {
    float2 local = float2(tileUv.x * tileSize, (1.0 - tileUv.y) * tileSize);
    float4 world = float4(tileOrigin + local, 0.0, 1.0);
    return camera.matrix * world;
}

static inline float4 globeClipFromTileUV(float2 localUv,
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

#endif
