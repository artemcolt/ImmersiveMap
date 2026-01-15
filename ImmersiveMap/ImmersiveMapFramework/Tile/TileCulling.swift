//
//  TileCulling.swift
//  ImmersiveMap
//
//  Created by Artem on 12/27/25.
//

class TileCulling {
    let camera: Camera
    private let debugLogging: Bool
    
    init(camera: Camera, debugLogging: Bool) {
        self.camera = camera
        self.debugLogging = debugLogging
    }
    
     func iSeeTilesGlobe(globe: Globe, targetZoom: Int, center: Center, viewMode: ViewMode, pan: SIMD2<Float>) -> Set<Tile> {
        let tileX = (Int) (center.tileX)
        let tileY = (Int) (center.tileY)
        
        if debugLogging {
            print("[CENTER] \(tileX), \(tileY), \(targetZoom)")
        }
        let rotation = camera.createRotationMatrix(globe: globe)
        var result: Set<Tile> = []
        camera.collectVisibleTilesGlobe(x: 0, y: 0, z: 0,
                                        targetZ: targetZoom,
                                        radius: globe.radius,
                                        rotation: rotation,
                                        result: &result,
                                        centerTile: Tile(x: tileX, y: tileY, z: targetZoom),
                                        mode: viewMode,
                                        pan: pan
        )
        
        // Удаляем все дубликаты из результата
        return result
    }
    
    func iSeeTilesFlat(targetZoom: Int, center: Center, pan: SIMD2<Double>, mapSize: Double) -> Set<Tile> {
       let tileX = (Int) (center.tileX)
       let tileY = (Int) (center.tileY)
       
       if debugLogging {
           print("[CENTER] \(tileX), \(tileY), \(targetZoom)")
       }
       var result: Set<Tile> = []
       camera.collectVisibleTilesFlat(x: 0, y: 0, z: 0,
                                      targetZ: targetZoom,
                                      result: &result,
                                      centerTile: Tile(x: tileX, y: tileY, z: targetZoom),
                                      pan: pan,
                                      mapSize: mapSize,
                                      shiftXMap: 0)
        
        // Собираем карту слева
        camera.collectVisibleTilesFlat(x: 0, y: 0, z: 0,
                                       targetZ: targetZoom,
                                       result: &result,
                                       centerTile: Tile(x: tileX, y: tileY, z: targetZoom),
                                       pan: pan,
                                       mapSize: mapSize,
                                       shiftXMap: -1)
        
        // Собираем карту cправа
        camera.collectVisibleTilesFlat(x: 0, y: 0, z: 0,
                                       targetZ: targetZoom,
                                       result: &result,
                                       centerTile: Tile(x: tileX, y: tileY, z: targetZoom),
                                       pan: pan,
                                       mapSize: mapSize,
                                       shiftXMap: 1)
        
       
       return result
   }
}
