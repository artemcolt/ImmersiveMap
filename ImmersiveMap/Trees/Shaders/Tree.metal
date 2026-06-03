// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  Tree.metal
//  ImmersiveMap
//

#include <metal_stdlib>
using namespace metal;
#include "../../Rendering/Shaders/Shared/RenderUniforms.h"

struct TreeVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 uv [[attribute(2)]];
    float baseScale [[attribute(3)]];
    float yawRadians [[attribute(4)]];
};

struct TreeTileUniform {
    float2 origin;
    float size;
    float runtimeScale;
    float yawFactor;
};

struct TreeMaterial {
    float3 color;
    float _padding0;
};

struct TreeLight {
    float4 direction;
    float4 color;
    float4 intensities;
};

struct TreeVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
};

static inline float2 rotate2D(float2 value, float radians) {
    float sine = sin(radians);
    float cosine = cos(radians);
    return float2(value.x * cosine - value.y * sine,
                  value.x * sine + value.y * cosine);
}

vertex TreeVertexOut treeVertexShader(TreeVertexIn vertexIn [[stage_in]],
                                      constant Camera& camera [[buffer(2)]],
                                      constant TreeTileUniform& tileUniform [[buffer(3)]]) {
    float yaw = vertexIn.yawRadians * tileUniform.yawFactor;
    float tileUnitToWorld = tileUniform.size / 4096.0;
    float instanceScale = vertexIn.baseScale * tileUniform.runtimeScale * tileUnitToWorld;

    float2 anchor = tileUniform.origin + vertexIn.uv * tileUniform.size;
    float2 horizontalLocal = rotate2D(float2(vertexIn.position.x, vertexIn.position.z) * instanceScale, yaw);
    float height = vertexIn.position.y * instanceScale;

    float3 worldPosition = float3(anchor + horizontalLocal, height);

    float3 baseNormal = float3(vertexIn.normal.x, vertexIn.normal.z, vertexIn.normal.y);
    float2 rotatedNormalXY = rotate2D(baseNormal.xy, yaw);
    float3 worldNormal = normalize(float3(rotatedNormalXY, baseNormal.z));

    TreeVertexOut out;
    out.position = camera.matrix * float4(worldPosition, 1.0);
    out.worldPosition = worldPosition;
    out.worldNormal = worldNormal;
    return out;
}

fragment float4 treeFragmentShader(TreeVertexOut in [[stage_in]],
                                   constant Camera& camera [[buffer(1)]],
                                   constant TreeLight& light [[buffer(2)]],
                                   constant TreeMaterial& material [[buffer(3)]]) {
    float3 normal = normalize(in.worldNormal);
    float3 lightDir = normalize(light.direction.xyz);
    float3 viewDir = normalize(camera.eye - in.worldPosition);

    float diffuseFactor = max(dot(normal, lightDir), 0.0);
    float3 reflectDir = reflect(-lightDir, normal);
    float specularFactor = diffuseFactor > 0.0
        ? pow(max(dot(viewDir, reflectDir), 0.0), light.intensities.w)
        : 0.0;

    float3 baseColor = material.color;
    float3 ambient = baseColor * light.intensities.x * light.color.rgb;
    float3 diffuse = baseColor * light.intensities.y * diffuseFactor * light.color.rgb;
    float3 specular = light.color.rgb * light.intensities.z * specularFactor;
    return float4(ambient + diffuse + specular, 1.0);
}
