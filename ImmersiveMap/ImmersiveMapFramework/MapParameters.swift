//
//  MapParameters.swift
//  ImmersiveMap
//
//  Created by Artem on 9/6/25.
//

import Foundation
import simd

public struct MapConfiguration {
    public struct StarfieldConfiguration {
        public var starCount: Int
        public var sizeMin: Float
        public var sizeMax: Float
        public var brightnessMin: Float
        public var brightnessMax: Float
        public var near: Float
        public var far: Float
        public var radiusScale: Float

        public init(starCount: Int,
                    sizeMin: Float,
                    sizeMax: Float,
                    brightnessMin: Float,
                    brightnessMax: Float,
                    near: Float,
                    far: Float,
                    radiusScale: Float) {
            self.starCount = starCount
            self.sizeMin = sizeMin
            self.sizeMax = sizeMax
            self.brightnessMin = brightnessMin
            self.brightnessMax = brightnessMax
            self.near = near
            self.far = far
            self.radiusScale = radiusScale
        }
    }

    public struct SpaceConfiguration {
        public var clearColor: SIMD4<Double>

        public init(clearColor: SIMD4<Double>) {
            self.clearColor = clearColor
        }
    }

    public struct CometConfiguration {
        public var enabled: Bool
        public var cometCount: Int
        public var sizeMin: Float
        public var sizeMax: Float
        public var brightnessMin: Float
        public var brightnessMax: Float
        public var durationMin: Float
        public var durationMax: Float
        public var cycleSeconds: Float
        public var tailScale: Float
        public var radiusScale: Float
        public var near: Float
        public var far: Float
        public var fadeOutSeconds: Float

        public init(enabled: Bool,
                    cometCount: Int,
                    sizeMin: Float,
                    sizeMax: Float,
                    brightnessMin: Float,
                    brightnessMax: Float,
                    durationMin: Float,
                    durationMax: Float,
                    cycleSeconds: Float,
                    tailScale: Float,
                    radiusScale: Float,
                    near: Float,
                    far: Float,
                    fadeOutSeconds: Float) {
            self.enabled = enabled
            self.cometCount = cometCount
            self.sizeMin = sizeMin
            self.sizeMax = sizeMax
            self.brightnessMin = brightnessMin
            self.brightnessMax = brightnessMax
            self.durationMin = durationMin
            self.durationMax = durationMax
            self.cycleSeconds = cycleSeconds
            self.tailScale = tailScale
            self.radiusScale = radiusScale
            self.near = near
            self.far = far
            self.fadeOutSeconds = fadeOutSeconds
        }
    }

    public var maxPitch: Float
    public var continueRendering: Bool
    public var debugAssemblingMap: Bool
    public var debugRenderLogging: Bool
    public var clearDownloadedOnDiskTiles: Bool
    public var addTestBorders: Bool
    public var maxConcurrentFetchs: Int
    public var maxFifoCapacity: Int
    public var maxCachedTilesMemInBytes: Int
    public var tileHoldSeconds: TimeInterval
    public var starfield: StarfieldConfiguration
    public var space: SpaceConfiguration
    public var comets: CometConfiguration

    public init(maxPitch: Float,
                continueRendering: Bool,
                debugAssemblingMap: Bool,
                debugRenderLogging: Bool,
                clearDownloadedOnDiskTiles: Bool,
                addTestBorders: Bool,
                maxConcurrentFetchs: Int,
                maxFifoCapacity: Int,
                maxCachedTilesMemInBytes: Int,
                tileHoldSeconds: TimeInterval,
                starfield: StarfieldConfiguration,
                space: SpaceConfiguration,
                comets: CometConfiguration) {
        self.maxPitch = maxPitch
        self.continueRendering = continueRendering
        self.debugAssemblingMap = debugAssemblingMap
        self.debugRenderLogging = debugRenderLogging
        self.clearDownloadedOnDiskTiles = clearDownloadedOnDiskTiles
        self.addTestBorders = addTestBorders
        self.maxConcurrentFetchs = maxConcurrentFetchs
        self.maxFifoCapacity = maxFifoCapacity
        self.maxCachedTilesMemInBytes = maxCachedTilesMemInBytes
        self.tileHoldSeconds = tileHoldSeconds
        self.starfield = starfield
        self.space = space
        self.comets = comets
    }

    public init(maxPitch: Float,
                continueRendering: Bool,
                debugAssemblingMap: Bool,
                debugRenderLogging: Bool,
                clearDownloadedOnDiskTiles: Bool,
                addTestBorders: Bool,
                maxConcurrentFetchs: Int,
                maxFifoCapacity: Int,
                maxCachedTilesMemInBytes: Int,
                tileHoldSeconds: TimeInterval) {
        self.init(maxPitch: maxPitch,
                  continueRendering: continueRendering,
                  debugAssemblingMap: debugAssemblingMap,
                  debugRenderLogging: debugRenderLogging,
                  clearDownloadedOnDiskTiles: clearDownloadedOnDiskTiles,
                  addTestBorders: addTestBorders,
                  maxConcurrentFetchs: maxConcurrentFetchs,
                  maxFifoCapacity: maxFifoCapacity,
                  maxCachedTilesMemInBytes: maxCachedTilesMemInBytes,
                  tileHoldSeconds: tileHoldSeconds,
                  starfield: MapConfiguration.default.starfield,
                  space: MapConfiguration.default.space,
                  comets: MapConfiguration.default.comets)
    }

    public static let `default` = MapConfiguration(
        maxPitch: Float.pi / 2.3,
        continueRendering: true,
        debugAssemblingMap: false,
        debugRenderLogging: false,
        clearDownloadedOnDiskTiles: false,
        addTestBorders: false,
        maxConcurrentFetchs: 5,
        maxFifoCapacity: 50,
        maxCachedTilesMemInBytes: 512 * 1024 * 1024,
        tileHoldSeconds: 3.0,
        starfield: StarfieldConfiguration(starCount: 2400,
                                          sizeMin: 2.2,
                                          sizeMax: 4.0,
                                          brightnessMin: 0.6,
                                          brightnessMax: 1.0,
                                          near: 0.1,
                                          far: 6000.0,
                                          radiusScale: 8.0),
        space: SpaceConfiguration(clearColor: SIMD4<Double>(0.02, 0.02, 0.05, 1.0)),
        comets: CometConfiguration(enabled: true,
                                   cometCount: 24,
                                   sizeMin: 10.0,
                                   sizeMax: 18.0,
                                   brightnessMin: 0.6,
                                   brightnessMax: 1.0,
                                   durationMin: 0.8,
                                   durationMax: 2.0,
                                   cycleSeconds: 90.0,
                                   tailScale: 18.0,
                                   radiusScale: 8.0,
                                   near: 0.1,
                                   far: 6000.0,
                                   fadeOutSeconds: 0.6)
    )
}
