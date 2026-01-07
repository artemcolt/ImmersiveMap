//
//  Tile.swift
//  TucikMap
//
//  Created by Artem on 5/30/25.
//

// Структура для представления тайла
import MetalKit
import Foundation


struct Tile: Hashable {
    let x: Int
    let y: Int
    let z: Int
    let loop: Int8
    let isMinimized: Bool // это чтобы далекие тайлы определять, они заменяются на карте на более мелкие тайлы
    
    static func == (lhs: Tile, rhs: Tile) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z && lhs.loop == rhs.loop
    }
    
    // Ручная реализация хэширования
    func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
        hasher.combine(z)
        hasher.combine(loop)
    }
    
    init(x: Int, y: Int, z: Int, loop: Int8 = 0, isMinimized: Bool = false) {
        self.x = x
        self.y = y
        self.z = z
        self.loop = loop
        self.isMinimized = isMinimized
    }
    
    // Проверяет, покрывает ли текущий тайл другой тайл
    func covers(_ other: Tile) -> Bool {
        // Тайл покрывает другой, если он имеет меньший уровень зума
        // и содержит координаты другого тайла
        if z >= other.z {
            return false
        }
        
        // Вычисляем масштаб между уровнями зума
        let scale = 1 << (other.z - z)
        
        // Проверяем, попадают ли координаты другого тайла в область текущего
        let minX = x * scale
        let maxX = (x + 1) * scale - 1
        let minY = y * scale
        let maxY = (y + 1) * scale - 1
        
        return other.x >= minX && other.x <= maxX &&
               other.y >= minY && other.y <= maxY
    }
    
    func findParentTile(atZoom targetZoom: Int, isMinimized: Bool = false) -> Tile? {
        // Проверяем, что текущий зум больше целевого (иначе родителя нет на targetZoom)
        guard z >= targetZoom, targetZoom >= 0 else {
            return nil
        }
        
        // Разница в уровнях зума
        let zoomDifference = z - targetZoom
        
        // Вычисляем координаты родительского тайла
        // Делим x и y на 2^(разница зумов), берём целую часть
        let parentX = x >> zoomDifference
        let parentY = y >> zoomDifference
        
        return Tile(x: parentX, y: parentY, z: targetZoom, loop: loop, isMinimized: isMinimized)
    }
}
