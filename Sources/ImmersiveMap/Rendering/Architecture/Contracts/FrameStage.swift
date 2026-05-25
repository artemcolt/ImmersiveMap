//
//  FrameStage.swift
//  ImmersiveMapFramework
//

import Foundation

enum FrameStage: String, CaseIterable {
    case collectInput
    case updateScene
    case prepareGPU
    case encodePasses
    case presentFrame
}
