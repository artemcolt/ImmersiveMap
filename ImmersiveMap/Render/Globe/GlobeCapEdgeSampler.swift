// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import simd

enum GlobeCapEdgeSampler {
    static func atlasSampleUV(latitude: Float,
                              longitude: Float,
                              tileData: GlobeTilesTexture.TileData) -> SIMD2<Float>? {
        let textureSize = Float(tileData.textureSize)
        let cellSize = Float(tileData.cellSize)
        guard textureSize > 0,
              cellSize > 0 else {
            return nil
        }

        let count = Int(textureSize / cellSize)
        guard count > 0 else {
            return nil
        }

        let tile = tileData.tile
        let zPow = Float(1 << Int(tile.z))
        let normalizedWorldX = wrapUnit(longitude / (2.0 * Float.pi))
        let mercatorY = yMercatorNormalized(latitude: latitude)
        let normalizedWorldY = (1.0 - mercatorY) * 0.5

        let localX = normalizedWorldX * zPow - Float(tile.x)
        let localY = normalizedWorldY * zPow - Float(tile.y)
        let epsilon: Float = 0.00001
        guard localX >= -epsilon,
              localX <= 1.0 + epsilon,
              localY >= -epsilon,
              localY <= 1.0 + epsilon else {
            return nil
        }

        let position = Int(tileData.position)
        let posU = position % count
        let posV = position / count
        let lastPos = count - 1
        let lastTile = Int(zPow) - 1

        let textureV = (mercatorY + 1.0) * 0.5
        let u = (normalizedWorldX * zPow - Float(tile.x) + Float(posU)) / Float(count)
        let v = (1.0 - textureV * zPow + Float(lastTile - Int(tile.y)) + Float(lastPos - posV)) / Float(count)

        let uvSize = 1.0 / Float(count)
        let halfTexel = 0.5 / textureSize
        let uMin = Float(posU) * uvSize
        let uMax = uMin + uvSize
        let vMin = Float(lastPos - posV) * uvSize
        let vMax = 1.0 - Float(posV) * uvSize

        return SIMD2<Float>(
            min(max(u, uMin + halfTexel), uMax - halfTexel),
            min(max(v, vMin + halfTexel), vMax - halfTexel)
        )
    }

    private static func wrapUnit(_ value: Float) -> Float {
        let wrapped = value.truncatingRemainder(dividingBy: 1.0)
        return wrapped < 0 ? wrapped + 1.0 : wrapped
    }

    private static func yMercatorNormalized(latitude: Float) -> Float {
        let sinLatitude = sin(latitude)
        let maxSinLatitude = tanh(Float.pi)
        let clamped = min(max(sinLatitude, -maxSinLatitude), maxSinLatitude)
        let yMercator = 0.5 * log((1.0 + clamped) / (1.0 - clamped))
        return yMercator / Float.pi
    }
}
