//
//  CameraUpdater.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Foundation
import simd

struct CameraUpdater {
    static func updateIfNeeded(camera: Camera, cameraControl: CameraControl) {
        guard cameraControl.update else {
            return
        }

        let yaw = cameraControl.yaw
        let pitch = cameraControl.pitch

        let zRemains = cameraControl.zoom.truncatingRemainder(dividingBy: 1.0)
        let camUp = SIMD3<Float>(0, 1, 0)
        let camPosition = SIMD3<Float>(0, 0, (1.0 - Float(zRemains) * 0.5))
        let camRight = SIMD3<Float>(1, 0, 0)

        let pitchQuat = simd_quatf(angle: pitch, axis: camRight)
        let yawQuat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 0, 1))

        camera.eye = simd_act(yawQuat * pitchQuat, camPosition)
        camera.up = simd_act(yawQuat * pitchQuat, camUp)

        camera.recalculateMatrix()

        // Мы камеру обновили, флаг возвращаем в исходное состояние
        // Когда в камере что-то меняется, то этот флаг становится true
        cameraControl.update = false
    }
}
