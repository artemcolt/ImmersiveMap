//
//  Common.metal
//  ImmersiveMap
//
//  Created by Artem on 9/4/25.
//

#include <metal_stdlib>
using namespace metal;

float4x4 rotationMatrix(float3 axis, float angle) {
    // Normalize the axis to ensure it's a unit vector
    axis = normalize(axis);
    
    float cosA = cos(angle);
    float sinA = sin(angle);
    float oneMinusCos = 1.0 - cosA;
    
    float x = axis.x;
    float y = axis.y;
    float z = axis.z;
    
    // Construct the rotation matrix
    float4x4 matrix;
    
    matrix[0][0] = cosA + x * x * oneMinusCos;
    matrix[0][1] = x * y * oneMinusCos - z * sinA;
    matrix[0][2] = x * z * oneMinusCos + y * sinA;
    matrix[0][3] = 0.0;
    
    matrix[1][0] = x * y * oneMinusCos + z * sinA;
    matrix[1][1] = cosA + y * y * oneMinusCos;
    matrix[1][2] = y * z * oneMinusCos - x * sinA;
    matrix[1][3] = 0.0;
    
    matrix[2][0] = x * z * oneMinusCos - y * sinA;
    matrix[2][1] = y * z * oneMinusCos + x * sinA;
    matrix[2][2] = cosA + z * z * oneMinusCos;
    matrix[2][3] = 0.0;
    
    matrix[3][0] = 0.0;
    matrix[3][1] = 0.0;
    matrix[3][2] = 0.0;
    matrix[3][3] = 1.0;
    
    return matrix;
}
