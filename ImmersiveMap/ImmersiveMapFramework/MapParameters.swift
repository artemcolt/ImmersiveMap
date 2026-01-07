//
//  MapParameters.swift
//  ImmersiveMap
//
//  Created by Artem on 9/6/25.
//

public struct MapConfiguration {
    public var maxPitch: Float
    public var continueRendering: Bool
    public var debugAssemblingMap: Bool
    public var debugRenderLogging: Bool
    public var clearDownloadedOnDiskTiles: Bool
    public var addTestBorders: Bool
    public var maxConcurrentFetchs: Int
    public var maxFifoCapacity: Int
    public var maxCachedTilesMemInBytes: Int

    public init(maxPitch: Float,
                continueRendering: Bool,
                debugAssemblingMap: Bool,
                debugRenderLogging: Bool,
                clearDownloadedOnDiskTiles: Bool,
                addTestBorders: Bool,
                maxConcurrentFetchs: Int,
                maxFifoCapacity: Int,
                maxCachedTilesMemInBytes: Int) {
        self.maxPitch = maxPitch
        self.continueRendering = continueRendering
        self.debugAssemblingMap = debugAssemblingMap
        self.debugRenderLogging = debugRenderLogging
        self.clearDownloadedOnDiskTiles = clearDownloadedOnDiskTiles
        self.addTestBorders = addTestBorders
        self.maxConcurrentFetchs = maxConcurrentFetchs
        self.maxFifoCapacity = maxFifoCapacity
        self.maxCachedTilesMemInBytes = maxCachedTilesMemInBytes
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
        maxCachedTilesMemInBytes: 512 * 1024 * 1024
    )
}
