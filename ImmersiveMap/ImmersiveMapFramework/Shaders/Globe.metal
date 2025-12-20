//
//  Globe.metal
//  ImmersiveMap
//
//  Created by Artem on 9/20/25.
//

#include <metal_stdlib>
using namespace metal;
#include "Common.h"

// Add necessary structures for transformation and rendering
struct VertexIn {
    float2 uv [[attribute(0)]];
};

struct VertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float2 texCoord;
    float uvSize;
    float posU;
    float posV;
    float lastPos;
    float halfTexel;  // For inset clamping and discard relaxation
};

struct Globe {
    float panX;
    float panY;
    float radius;
    float transition;
};

struct Tile {
    int position;
    int textureSize;
    int cellSize;
    int3 tile;
};

float wrap(float x, float size) {
    return x - size * floor((x + size * 0.5) / size);
}

float4x4 translationMatrix(float3 t) {
    return float4x4(
        float4(1, 0, 0, t.x),
        float4(0, 1, 0, t.y),
        float4(0, 0, 1, t.z),
        float4(0, 0, 0, 1)
    );
}

float getYMercNorm(float latitude) {
    float sin_pan = sin(latitude);
    float max_sin_pan = tanh(M_PI_F); // == sin(maxLatitude)
    float clamped_sin_pan = max(-max_sin_pan, min(max_sin_pan, sin_pan));
    float y_pan_merc = 0.5 * log((1.0 + clamped_sin_pan) / (1.0 - clamped_sin_pan));
    float panY_merc_norm = y_pan_merc / M_PI_F; // normalized to [-1, 1]
    return panY_merc_norm;
}

vertex VertexOut globeVertexShader(VertexIn vertexIn [[stage_in]],
                                   constant Camera& camera [[buffer(1)]],
                                   constant Globe& globe [[buffer(2)]],
                                   constant Tile* tile [[buffer(3)]],
                                   uint instanceId [[instance_id]]) {
    
    float vertexUvX = vertexIn.uv.x; // goes 0 to 1
    float vertexUvY = vertexIn.uv.y; // goes 0 to 1
    
    float globePanX = globe.panX; // goes -1 to 1
    float globePanY = globe.panY; // goes -1 to 1
    float transition = globe.transition; // from globe view to flat view
    
    
    float maxLatitude = 2.0 * atan(exp(M_PI_F)) - M_PI_2_F; // Max globe latitude
    
    // Map coordinates
    float latitude = globePanY * maxLatitude;
    float longitude = globePanX * M_PI_F;
    
    float distortion = cos(latitude);
    float widthScale = mix(distortion, 1.0, transition);
    
    float globeRadius = globe.radius;
    
    Tile tileData = tile[instanceId];
    
    float textureSize = tileData.textureSize;
    float cellSize = tileData.cellSize;
    int count = textureSize / cellSize;
    
    int tileX = tileData.tile.x;
    int tileY = tileData.tile.y;
    int tileZ = tileData.tile.z;
    
    int posU = tileData.position % count;
    int posV = tileData.position / count;
    int lastPos = count - 1;
    
    float4x4 matrix = camera.matrix;
    
    float mapSize = 2 * M_PI_F * globeRadius * distortion;
    
    float phi = -M_PI_F * vertexUvY;
    float theta = 2 * M_PI_F * vertexUvX;
     
    float x = globeRadius * sin(phi) * sin(theta);
    float y = globeRadius * cos(phi);
    float z = globeRadius * sin(phi) * cos(theta);
    float3 spherePosition = float3(x, y, z);
    
    // Рассчитываем текстурные координаты для наложения
    float u = 1.0 - vertexUvX;
    
    // Вращаем планету
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


    // Convert globePanY (-1..1) to a Mercator-aligned vertical pan so the flat map
    float panY_merc_norm = getYMercNorm(latitude);

    float halfMapSize = mapSize / 2.0;
    float posUvX =  wrap(vertexUvX * mapSize - halfMapSize + globePanX * halfMapSize, mapSize);
    
    
    //float posUvY = -vertexUvY * mapSize + halfMapSize - panY_merc_norm * halfMapSize;
    float lat_v = M_PI_F * vertexUvY - M_PI_2_F;      // [-pi/2..pi/2]
    float v_merc_norm = -getYMercNorm(lat_v);          // [-1..1]

    float posUvY = (v_merc_norm - panY_merc_norm) * halfMapSize;
    
    float4x4 translationM = translationMatrix(float3(0, 0, -globeRadius));
    float4 spherePositionTranslated = float4(spherePosition, 1.0) * rotation * translationM;
    float4 flatPosition = float4(posUvX, posUvY, 0, 1.0);
    
    float4 clipSphere = matrix * spherePositionTranslated;
    float4 clipFlat = matrix * flatPosition;
    
    float4 ndcSphere = clipSphere / clipSphere.w;
    float4 ndcFlat   = clipFlat   / clipFlat.w;

    float4 ndc = mix(ndcSphere, ndcFlat, transition);
    
    float zPow = pow(2.0, tileZ);
    int tilesCount = int(zPow);
    int lastTile = tilesCount - 1;
    
    
    float sphereV = (getYMercNorm(M_PI_F * vertexUvY - M_PI_2_F) - 1.0) / -2.0;
    //float v = mix(sphereV, 1.0 - vertexUvY, transition);
    float v = sphereV;
    float t_u = ((1.0 - u) * zPow - tileX + posU) / count;
    float t_v = (1.0 - v * zPow + (lastTile - tileY) + float(lastPos - posV)) / count;
    
    VertexOut out;
    out.position = float4(ndc.xyz, 1.0);
    out.pointSize = 5.0;
    out.texCoord = float2(t_u, t_v);
    out.uvSize = 1.0 / count;
    out.posU = posU;
    out.posV = posV;
    out.lastPos = lastPos;
    out.halfTexel = 0.5 / textureSize;
    return out;
}

fragment float4 globeFragmentShader(VertexOut in [[stage_in]], texture2d<float> texture [[texture(0)]]) {
    constexpr sampler textureSampler(filter::linear, mip_filter::linear, mag_filter::linear);
    
    float u = in.texCoord.x;
    float v = in.texCoord.y;
    float posU = in.posU;
    float posV = in.posV;
    float lastPos = in.lastPos;
    float uvSize = in.uvSize;
    
    // Compute tile bounds in atlas UV space
    float u_min = posU * uvSize;
    float u_max = u_min + uvSize;
    float v_min = float(lastPos - posV) * uvSize;
    float v_max = 1.0 - posV * uvSize;
    
    // Relax discard bounds to avoid precision-induced gaps
    float delta = in.halfTexel;
    if (v > v_max + delta || v < v_min - delta ||
        u > u_max + delta || u < u_min - delta) {
        discard_fragment();
    }
    
    // Inset clamp for sampling to prevent bleed from adjacent tiles
    float u_clamped = max(u_min + in.halfTexel, min(u_max - in.halfTexel, u));
    float v_clamped = max(v_min + in.halfTexel, min(v_max - in.halfTexel, v));
    
    float4 color = texture.sample(textureSampler, float2(u_clamped, v_clamped));
    return color;
}
