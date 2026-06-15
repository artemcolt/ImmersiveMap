// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#include <metal_stdlib>
using namespace metal;
#include "GlobeTransitionProjection.h"

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
    float3 normal;
    float3 worldPos;
    float transition;
    float2 nightLightsUV;
    float3 earthNormal;
};

struct CapVertexIn {
    float2 latLon [[attribute(0)]];
};

struct CapVertexOut {
    float4 position [[position]];
    float capAlpha;
    float absLatitude;
    float latitude;
    float longitude;
    float2 nightLightsUV;
    float3 normal;
    float3 worldPos;
    float3 earthNormal;
};

struct CapParams {
    float4 edgeColor;
    float4 fillColor;
    float blendStartAbsLatitude;
    float blendEndAbsLatitude;
    float4 sampleOptions;
};

struct Tile {
    int position;
    int textureSize;
    int cellSize;
    int layer;
    int3 tile;
};


vertex VertexOut globeVertexShader(VertexIn vertexIn [[stage_in]],
                                   constant Camera& camera [[buffer(1)]],
                                   constant Globe& globe [[buffer(2)]],
                                   constant Tile& tileData [[buffer(3)]]) {
    
    float vertexUvX = vertexIn.uv.x; // goes 0 to 1
    float vertexUvY = vertexIn.uv.y; // goes 0 to 1
    
    int tileX = tileData.tile.x;
    int tileY = tileData.tile.y;
    int tileZ = tileData.tile.z;
    
    float zPow = pow(2.0, tileZ);
    float size = 1.0 / zPow;
    
    vertexUvX = vertexUvX / zPow + size * tileX;
    
    float latNorth = atan(sinh(M_PI_F * (1.0 - 2.0 * tileY / zPow)));
    float latSouth = atan(sinh(M_PI_F * (1.0 - 2.0 * (tileY + 1) / zPow)));
    float vNorth = 1.0 - (latNorth + M_PI_2_F) / M_PI_F;
    float vSouth = 1.0 - (latSouth + M_PI_2_F) / M_PI_F;
    float vSize = abs(vSouth - vNorth);
    vertexUvY = vNorth + vertexUvY * vSize;
    
    
    float transition = globe.transition; // from globe view to flat view
    
    
    // Map coordinates
    float latitude = globeTransitionPanLatitude(globe);
    float longitude = globeTransitionPanLongitude(globe);
    
    float globeRadius = globe.radius;
    
    
    float textureSize = tileData.textureSize;
    float cellSize = tileData.cellSize;
    int count = textureSize / cellSize;
    
    
    int posU = tileData.position % count;
    int posV = tileData.position / count;
    int lastPos = count - 1;
    
    float4x4 matrix = camera.matrix;
    
    float mapSize = globeTransitionMapSize(globe, latitude);
    
    float phi = -M_PI_F * vertexUvY;
    float theta = 2 * M_PI_F * vertexUvX;
     
    float x = globeRadius * sin(phi) * sin(theta);
    float y = globeRadius * cos(phi);
    float z = globeRadius * sin(phi) * cos(theta);
    float3 spherePosition = float3(x, y, z);
    
    
    // Rotate the planet
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
    float panY_merc_norm = globeTransitionPanMercatorY(latitude);
    
    // `vertexUvY` grows top-to-bottom, so this intermediate latitude is sign-inverted
    // relative to geographic latitude and needs the extra negation below.
    float lat_v = M_PI_F * vertexUvY - M_PI_2_F;      // [-pi/2..pi/2]
    float flatMercatorY = -getYMercNorm(lat_v);       // geographic-Mercator sign in flat world space
    float2 flatWorldPosition = globeTransitionFlatWorldPosition(vertexUvX,
                                                                flatMercatorY,
                                                                globe,
                                                                mapSize,
                                                                panY_merc_norm);
    
    float4x4 translationM = translationMatrix(float3(0, 0, -globeRadius));
    float4 spherePositionTranslated = float4(spherePosition, 1.0) * rotation * translationM;
    float4 flatPosition = float4(flatWorldPosition, 0, 1.0);
    float4 position = mix(spherePositionTranslated, flatPosition, transition);
    float4 clip = matrix * position;
    // Compute texture coordinates for blending
    float u = 1.0 - vertexUvX;
    
    int tilesCount = int(zPow);
    int lastTile = tilesCount - 1;
    float sphereV = (-flatMercatorY - 1.0) / -2.0;
    float v = sphereV;
    float t_u = ((1.0 - u) * zPow - tileX + posU) / count;
    float t_v = (1.0 - v * zPow + (lastTile - tileY) + float(lastPos - posV)) / count;
    
    VertexOut out;
    // Keep clip-space position; GPU performs the perspective divide.
    out.position = clip;
    out.pointSize = 5.0;
    out.texCoord = float2(t_u, t_v);
    out.uvSize = 1.0 / count;
    out.posU = posU;
    out.posV = posV;
    out.lastPos = lastPos;
    out.halfTexel = 0.5 / textureSize;
    out.normal = normalize((float4(spherePosition, 0.0) * rotation).xyz);
    out.worldPos = spherePositionTranslated.xyz;
    out.transition = transition;
    out.nightLightsUV = float2(vertexUvX, vertexUvY);
    out.earthNormal = normalize(spherePosition);
    return out;
}

static float nightLightsMask(texture2d<float> nightLightsTexture, float2 uv) {
    constexpr sampler sampler2d(filter::linear, address::repeat, mip_filter::linear);
    return nightLightsTexture.sample(sampler2d, uv).r;
}

struct GlobeCapAtlasSample {
    float2 uv;
    bool isValid;
};

static float globeCapWrapUnit(float value) {
    return value - floor(value);
}

static GlobeCapAtlasSample globeCapAtlasSampleUV(float latitude,
                                                 float longitude,
                                                 constant Tile& tileData) {
    float textureSize = float(tileData.textureSize);
    float cellSize = float(tileData.cellSize);
    if (textureSize <= 0.0 || cellSize <= 0.0) {
        return GlobeCapAtlasSample{float2(0.0), false};
    }

    int count = int(textureSize / cellSize);
    if (count <= 0) {
        return GlobeCapAtlasSample{float2(0.0), false};
    }

    int tileX = tileData.tile.x;
    int tileY = tileData.tile.y;
    int tileZ = tileData.tile.z;
    float zPow = exp2(float(tileZ));
    float normalizedWorldX = globeCapWrapUnit(longitude / (2.0 * M_PI_F));
    float mercatorY = getYMercNorm(latitude);
    float normalizedWorldY = (1.0 - mercatorY) * 0.5;

    float localX = normalizedWorldX * zPow - float(tileX);
    float localY = normalizedWorldY * zPow - float(tileY);
    float epsilon = 0.00001;
    if (localX < -epsilon || localX > 1.0 + epsilon ||
        localY < -epsilon || localY > 1.0 + epsilon) {
        return GlobeCapAtlasSample{float2(0.0), false};
    }

    int position = tileData.position;
    int posU = position % count;
    int posV = position / count;
    int lastPos = count - 1;
    int lastTile = int(zPow) - 1;
    float textureV = (mercatorY + 1.0) * 0.5;
    float u = (normalizedWorldX * zPow - float(tileX) + float(posU)) / float(count);
    float v = (1.0 - textureV * zPow + float(lastTile - tileY) + float(lastPos - posV)) / float(count);

    float uvSize = 1.0 / float(count);
    float halfTexel = 0.5 / textureSize;
    float uMin = float(posU) * uvSize;
    float uMax = uMin + uvSize;
    float vMin = float(lastPos - posV) * uvSize;
    float vMax = 1.0 - float(posV) * uvSize;

    return GlobeCapAtlasSample{
        float2(clamp(u, uMin + halfTexel, uMax - halfTexel),
               clamp(v, vMin + halfTexel, vMax - halfTexel)),
        true
    };
}

fragment float4 globeFragmentShader(VertexOut in [[stage_in]],
                                    texture2d<float> texture [[texture(0)]],
                                    texture2d<float> nightLightsTexture [[texture(1)]],
                                    constant Camera& camera [[buffer(1)]],
                                    constant EarthScene& earthScene [[buffer(2)]]) {
    constexpr sampler textureSampler(filter::linear, mip_filter::linear, mag_filter::linear);
    
//    return float4(1.0, 0, 0, 1);
    
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
        return float4(1.0, 0, 0, 1.0);
        //discard_fragment();
    }
    
    // Inset clamp for sampling to prevent bleed from adjacent tiles
    float u_clamped = max(u_min + in.halfTexel, min(u_max - in.halfTexel, u));
    float v_clamped = max(v_min + in.halfTexel, min(v_max - in.halfTexel, v));
    
    float4 color = texture.sample(textureSampler, float2(u_clamped, v_clamped));
    if (earthScene.isEnabled != 0) {
        float sunDot = dot(normalize(in.earthNormal), normalize(earthScene.sunDirection));
        float dayFactor = smoothstep(-earthScene.terminatorFadeWidth,
                                     earthScene.terminatorFadeWidth,
                                     sunDot);
        float dayBrightness = mix(earthScene.daySideMinimumBrightness, 1.0, dayFactor);
        float surfaceBrightness = mix(earthScene.nightSideBrightness, dayBrightness, dayFactor);
        surfaceBrightness = mix(surfaceBrightness, 1.0, in.transition);
        color.rgb *= surfaceBrightness;

        if (earthScene.nightLightsEnabled != 0) {
            float nightFactor = 1.0 - smoothstep(-earthScene.nightLightsTerminatorFadeWidth,
                                                 earthScene.nightLightsTerminatorFadeWidth,
                                                 sunDot);
            float mask = nightLightsMask(nightLightsTexture, in.nightLightsUV);
            float3 warmLight = float3(1.0, 0.72, 0.36);
            float3 coolLight = float3(0.65, 0.78, 1.0);
            float3 lightColor = mix(warmLight, coolLight, pow(mask, 1.8));
            color.rgb += lightColor * mask * nightFactor * earthScene.nightLightsIntensity * (1.0 - in.transition);
        }
    }

    float3 viewDir = normalize(camera.eye - in.worldPos);
    float rim = pow(max(0.0, 1.0 - dot(in.normal, viewDir)), 2.35);
    float outerGlow = pow(max(0.0, 1.0 - dot(in.normal, viewDir)), 5.2);
    float glowStrength = rim * 0.38 * (1.0 - in.transition);
    float3 innerGlowColor = float3(0.28, 0.54, 1.0) * glowStrength;
    float3 outerGlowColor = float3(0.08, 0.22, 0.72) * outerGlow * 0.22 * (1.0 - in.transition);
    color.rgb += innerGlowColor + outerGlowColor;
    return color;
}

vertex CapVertexOut globeCapVertexShader(CapVertexIn vertexIn [[stage_in]],
                                         constant Camera& camera [[buffer(1)]],
                                         constant Globe& globe [[buffer(2)]]) {
    float lat = vertexIn.latLon.x;
    float lon = vertexIn.latLon.y;
    
    float globeRadius = globe.radius;
    // Cap geometry stores geographic latitude directly. The globe tile path uses
    // phi = geographicLatitude - pi/2 after Mercator->sphere conversion, so caps
    // must use the same convention or north/south hemispheres get swapped.
    float phi = lat - M_PI_2_F;
    float theta = lon;
    
    float x = globeRadius * sin(phi) * sin(theta);
    float y = globeRadius * cos(phi);
    float z = globeRadius * sin(phi) * cos(theta);
    float3 spherePosition = float3(x, y, z);
    
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
    
    float4x4 translationM = translationMatrix(float3(0, 0, -globeRadius));
    float4 spherePositionTranslated = float4(spherePosition, 1.0) * rotation * translationM;
    float4 clip = camera.matrix * spherePositionTranslated;
    
    float transitionFade = clamp(globe.transition, 0.0, 1.0);
    
    CapVertexOut out;
    out.position = clip;
    out.capAlpha = 1.0 - transitionFade;
    out.absLatitude = abs(lat);
    out.latitude = lat;
    out.longitude = lon;
    out.nightLightsUV = float2(globeCapWrapUnit(lon / (2.0 * M_PI_F)),
                               1.0 - (lat + M_PI_2_F) / M_PI_F);
    out.normal = normalize((float4(spherePosition, 0.0) * rotation).xyz);
    out.worldPos = spherePositionTranslated.xyz;
    out.earthNormal = normalize(spherePosition);
    return out;
}

fragment float4 globeCapFragmentShader(CapVertexOut in [[stage_in]],
                                       texture2d<float> texture [[texture(0)]],
                                       texture2d<float> nightLightsTexture [[texture(1)]],
                                       constant CapParams& params [[buffer(0)]],
                                       constant Camera& camera [[buffer(1)]],
                                       constant EarthScene& earthScene [[buffer(2)]],
                                       constant Tile& tileData [[buffer(3)]]) {
    constexpr sampler textureSampler(filter::linear, mip_filter::linear, mag_filter::linear);

    float seamBlend = smoothstep(params.blendStartAbsLatitude,
                                 params.blendEndAbsLatitude,
                                 in.absLatitude);
    float4 color;
    if (params.sampleOptions.y > 0.5) {
        GlobeCapAtlasSample sample = globeCapAtlasSampleUV(params.sampleOptions.x,
                                                           in.longitude,
                                                           tileData);
        if (!sample.isValid) {
            discard_fragment();
            return float4(0.0);
        }
        color = texture.sample(textureSampler, sample.uv);
    } else {
        color = mix(params.edgeColor, params.fillColor, seamBlend);
    }

    if (earthScene.isEnabled != 0) {
        float sunDot = dot(normalize(in.earthNormal), normalize(earthScene.sunDirection));
        float dayFactor = smoothstep(-earthScene.terminatorFadeWidth,
                                     earthScene.terminatorFadeWidth,
                                     sunDot);
        float dayBrightness = mix(earthScene.daySideMinimumBrightness, 1.0, dayFactor);
        float surfaceBrightness = mix(earthScene.nightSideBrightness, dayBrightness, dayFactor);
        surfaceBrightness = mix(surfaceBrightness, 1.0, clamp(1.0 - in.capAlpha, 0.0, 1.0));
        color.rgb *= surfaceBrightness;

        if (earthScene.nightLightsEnabled != 0) {
            float nightFactor = 1.0 - smoothstep(-earthScene.nightLightsTerminatorFadeWidth,
                                                 earthScene.nightLightsTerminatorFadeWidth,
                                                 sunDot);
            float mask = nightLightsMask(nightLightsTexture, in.nightLightsUV);
            float3 warmLight = float3(1.0, 0.72, 0.36);
            float3 coolLight = float3(0.65, 0.78, 1.0);
            float3 lightColor = mix(warmLight, coolLight, pow(mask, 1.8));
            color.rgb += lightColor * mask * nightFactor * earthScene.nightLightsIntensity * in.capAlpha;
        }
    }

    float3 viewDir = normalize(camera.eye - in.worldPos);
    float rim = pow(max(0.0, 1.0 - dot(in.normal, viewDir)), 2.35);
    float outerGlow = pow(max(0.0, 1.0 - dot(in.normal, viewDir)), 5.2);
    float glowStrength = rim * 0.38 * in.capAlpha;
    float3 glowColor = float3(0.28, 0.54, 1.0) * glowStrength
        + float3(0.08, 0.22, 0.72) * outerGlow * 0.22 * in.capAlpha;

    color.rgb += glowColor;
    color.a *= in.capAlpha;
    return color;
}
