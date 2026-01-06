//
//  TileSorter.swift
//  ImmersiveMap
//
//  Created by Artem on 1/6/26.
//

import Foundation

struct TileSorter {
    static func sortForRendering(_ tiles: Set<Tile>, center: Center) -> [Tile] {
        return Array(tiles).sorted(by: { t1, t2 in
            if t1.z != t2.z {
                // Сперва тайлы, которые занимают меньшую площадь
                // То есть с большим z
                return t1.z > t2.z
            }

            let dx1 = abs(t1.x - Int(center.tileX))
            let dy1 = abs(t1.y - Int(center.tileY))
            let d1 = dx1 + dy1

            let dx2 = abs(t2.x - Int(center.tileX))
            let dy2 = abs(t2.y - Int(center.tileY))
            let d2 = dx2 + dy2

            // Сперва тайлы, которые ближе всего к центру
            return d1 < d2 // true -> элементы остаются на месте
        })
    }
}
