//
//  TileCulling.swift
//  ImmersiveMap
//
//  Created by Artem on 12/27/25.
//

class TileCulling {
    let camera: Camera
    
    init(camera: Camera) {
        self.camera = camera
    }
    
     func iSeeTilesGlobe(globe: Globe, targetZoom: Int, center: Center, viewMode: ViewMode, pan: SIMD2<Float>) -> Set<Tile> {
        let tileX = (Int) (center.tileX)
        let tileY = (Int) (center.tileY)
        
        print("[CENTER] \(tileX), \(tileY), \(targetZoom)")
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
    
    func iSeeTilesFlat(targetZoom: Int, center: Center, pan: SIMD2<Double>, radius: Double) -> Set<Tile> {
       let tileX = (Int) (center.tileX)
       let tileY = (Int) (center.tileY)
       
       print("[CENTER] \(tileX), \(tileY), \(targetZoom)")
       var result: Set<Tile> = []
       camera.collectVisibleTilesFlat(x: 0, y: 0, z: 0,
                                      targetZ: targetZoom,
                                      result: &result,
                                      centerTile: Tile(x: tileX, y: tileY, z: targetZoom),
                                      pan: pan, radius: radius
       )
       
       // Удаляем все дубликаты из результата
       return result
   }
}
