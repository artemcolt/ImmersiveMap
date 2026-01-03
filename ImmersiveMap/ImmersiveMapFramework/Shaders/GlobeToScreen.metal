//
//  GlobeToScreen.metal
//  ImmersiveMap
//
//  Created by Artem on 1/2/26.
//

#include <metal_stdlib>
using namespace metal;
#include "Common.h"

struct TilePointInput {
    float2 uv;    // Local UV inside the tile [0..1]
    int3 tile;    // Tile coordinate (x, y, z)
};

struct ScreenParams {
    float2 viewportSize; // In pixels; used only when outputPixels != 0
    uint outputPixels;   // 0 = NDC, 1 = pixels
};

struct ScreenPointOutput {
    float2 position; // NDC or pixel position, depending on outputPixels
    float depth;     // Clip-space depth (z / w)
    uint visible;    // 0 = clipped/behind, 1 = visible
};

struct CollisionParams {
    uint count;
    uint3 padding;
};

float4 globeClipFromTileUV(float2 localUv,
                           int3 tile,
                           constant Camera& camera,
                           constant Globe& globe) {
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

    float4x4 translationM = translationMatrix(float3(0, 0, -globeRadius));
    float4 spherePositionTranslated = float4(spherePosition, 1.0) * rotation * translationM;
    float4 flatPosition = float4(posUvX, posUvY, 0, 1.0);
    float4 position = mix(spherePositionTranslated, flatPosition, transition);
    return camera.matrix * position;
}

kernel void globeTileToScreenKernel(const device TilePointInput* inputs [[buffer(0)]],
                                    device ScreenPointOutput* outputs [[buffer(1)]],
                                    constant Camera& camera [[buffer(2)]],
                                    constant Globe& globe [[buffer(3)]],
                                    constant ScreenParams& screenParams [[buffer(4)]],
                                    uint gid [[thread_position_in_grid]]) {
    TilePointInput input = inputs[gid];
    float4 clip = globeClipFromTileUV(input.uv, input.tile, camera, globe);

    ScreenPointOutput result;
    if (clip.w <= 0.0) {
        result.position = float2(0.0);
        result.depth = 0.0;
        result.visible = 0;
        outputs[gid] = result;
        return;
    }

    float2 ndc = clip.xy / clip.w; // [-1..1]
    float depth = clip.z / clip.w;
    float2 position = ndc;

    if (screenParams.outputPixels != 0 && all(screenParams.viewportSize > 0.0)) {
        // TODO: flip Y or adjust for your viewport origin if needed.
        position = (ndc * 0.5 + 0.5) * screenParams.viewportSize;
    }

    result.position = position;
    result.depth = depth;
    result.visible = 1;
    outputs[gid] = result;
}

kernel void globeLabelCollisionKernel(const device ScreenPointOutput* points [[buffer(0)]],
                                      device uint* visibility [[buffer(1)]],
                                      const device float2* sizes [[buffer(2)]],
                                      constant CollisionParams& params [[buffer(3)]],
                                      uint gid [[thread_position_in_grid]]) {
    if (gid >= params.count) {
        return;
    }
    
    ScreenPointOutput point = points[gid];
    if (point.visible == 0) {
        visibility[gid] = 0;
        return;
    }
    
    float2 pos = point.position;
    float2 halfSize = sizes[gid] * 0.5;
    
    for (uint i = 0; i < gid; i++) {
        ScreenPointOutput other = points[i];
        if (other.visible == 0) {
            continue;
        }
        
        float2 d = abs(pos - other.position);
        float2 otherHalfSize = sizes[i] * 0.5;
        float2 overlap = halfSize + otherHalfSize;
        if (d.x < overlap.x && d.y < overlap.y) {
            visibility[gid] = 0;
            return;
        }
    }
    
    visibility[gid] = 1;
}
