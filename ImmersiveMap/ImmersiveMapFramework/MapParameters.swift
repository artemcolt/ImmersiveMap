//
//  MapParameters.swift
//  ImmersiveMap
//
//  Created by Artem on 9/6/25.
//

class MapParameters {
    static var maxPitch: Float = Float.pi / 2.3
    
    static var debugAssemblingMap: Bool = false
    static var clearDownloadedOnDiskTiles: Bool = false
    static var addTestBorders: Bool = false
    static var maxConcurrentFetchs: Int = 1
    static var maxFifoCapacity: Int = 50
    static var maxCachedTilesMemInBytes: Int = 500 * 1024 * 1024
}
