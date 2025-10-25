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
    float xRotation;
    float yRotation;
    float radius;
};

struct Tile {
    int position;
    int textureSize;
    int cellSize;
    int3 tile;
};


vertex VertexOut globeVertexShader(VertexIn vertexIn [[stage_in]],
                                   constant Camera& camera [[buffer(1)]],
                                   constant Globe& globe [[buffer(2)]],
                                   constant Tile* tile [[buffer(3)]],
                                   uint instanceId [[instance_id]]) {
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
    
    float radius = globe.radius;
    float4x4 matrix = camera.matrix;
    
    float phi = -M_PI_F * vertexIn.uv.y;
    float theta = 2 * M_PI_F * vertexIn.uv.x;
     
    float x = radius * sin(phi) * sin(theta);
    float y = radius * cos(phi);
    float z = radius * sin(phi) * cos(theta);
    
    float3 position = float3(x, y, z);
    float u = 1.0 - vertexIn.uv.x;
    
    // Adjust for Web Mercator projection (non-linear vertically)
    float v = vertexIn.uv.y;
    float lat = M_PI_F / 2.0 - phi;
    float sin_lat = sin(lat);
    float max_sin = tanh(M_PI_F);
    float clamped_sin = max(-max_sin, min(max_sin, sin_lat));
    float y_merc = 0.5 * log((1.0 + clamped_sin) / (1.0 - clamped_sin));
    v = (y_merc + M_PI_F) / (2.0 * M_PI_F);
    
    float cx = cos(-globe.xRotation);
    float sx = sin(-globe.xRotation);
    float cy = cos(-globe.yRotation);
    float sy = sin(-globe.yRotation);

    float4x4 rotation = float4x4(
        float4(cy,        0,         -sy,       0),  // Колонка 0
        float4(sy * sx,   cx,        cy * sx,   0),  // Колонка 1
        float4(sy * cx,  -sx,        cy * cx,   0),  // Колонка 2
        float4(0,         0,          0,        1)   // Колонка 3
    );
    
    float4 worldPosition = float4(position, 1.0) * rotation - float4(0, 0, radius, 0);
    float4 clipPosition = matrix * worldPosition;
    
    float zPow = pow(2.0, tileZ);
    int tilesCount = int(zPow);
    int lastTile = tilesCount - 1;
    
    float t_u = ((1.0 - u) * zPow - tileX + posU) / count;
    float t_v = (1.0 - v * zPow + (lastTile - tileY) + float(lastPos - posV)) / count;
    
    VertexOut out;
    out.position = clipPosition;
    out.pointSize = 5.0;
    out.texCoord = float2(t_u, t_v);
    out.uvSize = 1.0 / count;
    out.posU = posU;
    out.posV = posV;
    out.lastPos = lastPos;
    out.halfTexel = 0.5 / textureSize;
    return out;
}

fragment float4 globeFragmentShader(VertexOut in [[stage_in]],
                                    texture2d<float> texture [[texture(0)]]) {
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
