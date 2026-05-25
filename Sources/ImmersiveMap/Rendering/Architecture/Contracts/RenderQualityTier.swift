//
//  RenderQualityTier.swift
//  ImmersiveMapFramework
//

import Foundation

enum RenderQualityTier {
    case low
    case standard
    case high

    static func from(zoom: Double) -> RenderQualityTier {
        if zoom < 7.0 {
            return .low
        }
        if zoom < 13.0 {
            return .standard
        }
        return .high
    }
}
