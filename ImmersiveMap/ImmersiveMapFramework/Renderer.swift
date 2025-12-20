//
//  Renderer.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import Foundation
import simd
import Metal
import MetalKit
import QuartzCore // Для CAMetalLayer

class Renderer {
    private let metalLayer: CAMetalLayer
    let metalDevice: MTLDevice
    let commandQueue: MTLCommandQueue
    let vertexBuffer: MTLBuffer
    let parameters: Parameters
    let polygonPipeline: PolygonsPipeline
    let tilePipeline: TilePipeline
    let globePipeline: GlobePipeline
    let camera: Camera
    let cameraControl: CameraControl
    var transition: Float = 0
    private var metalTilesStorage: MetalTilesStorage?
    private let tilesTexture: TilesTexture
    private let textRenderer: TextRenderer
    private let uiView: ImmersiveMapUIView
    
    private let sphereVerticesBuffer: MTLBuffer
    private let sphereIndicesBuffer: MTLBuffer
    private let sphereIndicesCount: Int
    private var lastDrawableSize: CGSize = .zero
    private let maxLatitude = 2.0 * atan(exp(Double.pi)) - Double.pi / 2.0
    
    private let semaphore = DispatchSemaphore(value: 3)
    private var currentIndex = 0
    
    private let startDate = Date()
    private var previousSeeTilesHash: Int = 0
    private var savedSeeTiles: [Tile] = []
    private var savedTiles: [PlaceTile] = []
    private var previousZoom: Int
    private var previousStorageHash: Int = 0
    private let tile: Tile = Tile(x: 0, y: 0, z: 0)
    private var screenMatrix: matrix_float4x4?
    private var screenMatrixSize: CGSize = CGSize.zero
    
    private var tileTextVerticesBuffer: MTLBuffer
    private var previousTilesTextKey: String = ""
    private var tileTextVerticesCount: Int = 0
    
    let vertices: [PolygonsPipeline.Vertex] = [
        // axes
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(1, 0, 0, 1)),
        PolygonsPipeline.Vertex(position: SIMD4<Float>(1.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(1, 0, 0, 1)),
        
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(0, 1, 0, 1)),
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 1.0, 0.0, 1.0),   color: SIMD4<Float>(0, 1, 0, 1)),
        
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(0, 0, 1, 1)),
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 1.0, 1.0),   color: SIMD4<Float>(0, 0, 1, 1)),
    ]
    
    init(layer: CAMetalLayer, uiView: ImmersiveMapUIView) {
        self.metalLayer = layer
        self.uiView = uiView
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal не поддерживается на этом устройстве")
        }
        self.parameters = Parameters()
        self.metalDevice = metalDevice
        layer.device = metalDevice
        layer.pixelFormat = .bgra8Unorm
        
        guard let queue = metalDevice.makeCommandQueue() else {
            fatalError("Не удалось создать command queue")
        }
        self.commandQueue = queue
        
        // Создаём вершинный буфер
        vertexBuffer = metalDevice.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<PolygonsPipeline.Vertex>.stride, options: [])!
            
        let bundle = Bundle(for: Renderer.self)
        let library = try! metalDevice.makeDefaultLibrary(bundle: bundle)
        
        polygonPipeline = PolygonsPipeline(metalDevice: metalDevice, layer: layer, library: library)
        tilePipeline = TilePipeline(metalDevice: metalDevice, layer: layer, library: library)
        globePipeline = GlobePipeline(metalDevice: metalDevice, layer: layer, library: library)
        
        textRenderer = TextRenderer(device: metalDevice, library: library)
        tilesTexture = TilesTexture(metalDevice: metalDevice, tilePipeline: tilePipeline)
        camera = Camera()
        cameraControl = CameraControl()
        cameraControl.setZoom(zoom: 0)
        //cameraControl.setLatLonDeg(latDeg: 55.751244, lonDeg: 37.618423)
        previousZoom = Int(cameraControl.zoom)
        
        let sphereGeometry = SphereGeometry(stacks: 64, slices: 64)
        let vertices = sphereGeometry.vertices
        let indices = sphereGeometry.indices
        sphereVerticesBuffer = metalDevice.makeBuffer(bytes: vertices, length: MemoryLayout<SphereGeometry.Vertex>.stride * vertices.count)!
        sphereIndicesBuffer = metalDevice.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count)!
        sphereIndicesCount = indices.count
        
        let len = MemoryLayout<TextVertex>.stride * 4000
        tileTextVerticesBuffer = metalDevice.makeBuffer(length: len)!
        
        metalTilesStorage = MetalTilesStorage(mapStyle: DefaultMapStyle(), metalDevice: metalDevice, renderer: self)
    }
        
    func newTileAvailable(tile: Tile) {
        uiView.redraw = true
    }
    
    func render(to layer: CAMetalLayer) {
        semaphore.wait()
        
        let currentDrawableSize = layer.drawableSize
        if currentDrawableSize.width == 0 || currentDrawableSize.height == 0 {
            return
        }
        
        // При изменении размера экрана пересчитываем матрицы вида.
        if currentDrawableSize != lastDrawableSize {
            let aspect = Float(currentDrawableSize.width) / Float(currentDrawableSize.height)
            camera.recalculateProjection(aspect: aspect)
            lastDrawableSize = currentDrawableSize
        }
        
        // Экранная матрица для размещения 2д элементов на экране
        if screenMatrixSize != currentDrawableSize {
            screenMatrixSize = currentDrawableSize
            screenMatrix = Matrix.orthographicMatrix(left: 0, right: Float(screenMatrixSize.width),
                                                     bottom: 0, top: Float(screenMatrixSize.height),
                                                     near: -1, far: 1)
        }
        
        // Без экранной матрицы не можем продолжить рендринг
        guard var screenMatrix = screenMatrix else {
            return
        }

        
        // Не используем tripple buffering
        // На моем телефоне и без него хорошо работает
        let nextIndex = (currentIndex + 1) % 3
        currentIndex = nextIndex
        currentIndex = 0
        
        // Движение камеры
        if cameraControl.update {
            let yaw = cameraControl.yaw
            let pitch = cameraControl.pitch
            
            let zRemains = cameraControl.zoom.truncatingRemainder(dividingBy: 1.0)
            let camUp = SIMD3<Float>(0, 1, 0)
            let camPosition = SIMD3<Float>(0, 0, (1.0 - zRemains * 0.5))
            let camRight = SIMD3<Float>(1, 0, 0)
            
            let pitchQuat = simd_quatf(angle: pitch, axis: camRight)
            let yawQuat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 0, 1))
            
            camera.eye = simd_act(yawQuat * pitchQuat, camPosition)
            camera.up = simd_act(yawQuat * pitchQuat, camUp)
            
            camera.recalculateMatrix()
            
            // Мы камеру обновили, флаг возвращаем в исходное состояние
            // Когда в камере что-то меняется, то этот флаг становится true
            cameraControl.update = false
        }
        
        guard let cameraMatrix = camera.cameraMatrix,
              let drawable = layer.nextDrawable() else {
            semaphore.signal()
            return
        }
        
        let clearColor = parameters.clearColor
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        // При увеличении зума, мы масштабируем глобус, возвращая камеру в исходное нулевое положение
        let worldScale = pow(2.0, floor(cameraControl.zoom))
        let z = cameraControl.zoom
        let from = Float(5.0)
        let span = Float(1.0)
        let to = from + span
        //var transition = max(0.0, min(1.0, (z - from) / (to - from)))
        // Sinusoidal transition driven by time (0..1). Uses time since startDate for stability.
        let t = Float(Date().timeIntervalSince(startDate))
        let speed: Float = 1.0 // cycles per ~2π seconds; increase for faster oscillation
        transition = (sinf(t * speed) + 1.0) * 0.5
        var globe = Globe(panX: Float(cameraControl.pan.x),
                          panY: Float(cameraControl.pan.y),
                          radius: 0.14 * worldScale,
                          transition: Float(transition))
//        print("xRotation: \(xRotation), yRotation: \(yRotation)")
        
        
        // Получаем текущий центральный тайл
        let zoom = Int(cameraControl.zoom)
        let center = getCenter(targetZoom: zoom)
        
        
        // Тайлы, которые пользователь видит в полностью подгруженном состоянии
        // они там могут быть в разнобой, просто все тайлы, которые пользователь видит
        let seeTiles = iSeeTiles(globe: globe, targetZoom: zoom, center: center)
        let seeTilesHash = seeTiles.hashValue
        
        // Если мы видим такие же тайлы, что и на предыдущем кадре, то тогда нету смысла обрабатывать их опять
        // Использовать тайлы с предыдущего кадра
        if previousSeeTilesHash != seeTilesHash {
            print("Previous see tiles hash changed")
            // Сортируем тайлы для правильной, последовательной отрисовки
            savedSeeTiles = Array(seeTiles).sorted(by: { t1, t2 in
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
            previousSeeTilesHash = seeTilesHash
        }
        
        print("- - -")
        print("count = \(savedSeeTiles.count)")
        for i in 0..<savedSeeTiles.count {
            let sortedSeeTile = savedSeeTiles[i]
            print("\(i+1)) x=\(sortedSeeTile.x), y=\(sortedSeeTile.y), z=\(sortedSeeTile.z)")
        }
        
        
        // Запрашиваем тайлы, которые нужны для отрисовки карты
        // Тайлы, которых нету будут запрошены по интернету и так же будет попытка локальной загрузки с диска
        var storageHash = Int(0)
        let tilesFromStorage = metalTilesStorage!.request(tiles: savedSeeTiles, hash: &storageHash)
        
        
        // Перерисовываем только если загруженные тайлы другие
        if previousStorageHash != storageHash {
            print("Tiles storage hash changed")
            // Заменяем пробелы тайлами из предыдущего кадра.
            var placeTiles: [PlaceTile] = []
            let tileDepthCount = TileDepthCount()
            for i in 0..<tilesFromStorage.count {
                let storageTile = tilesFromStorage[i]
                let metalTile = storageTile.metalTile
                let tile = storageTile.tile
                
                // Ищем один тайл, который полностью покрывает необходимый
                func findFullReplacement() -> Bool? {
                    for prev in savedTiles {
                        let prevMetalTile = prev.metalTile
                        let prevTile = prev.metalTile.tile
                        
                        // Предыдущий тайл полностью покрывает наш необходимый тайл
                        if prevTile.covers(tile) {
                            guard let depth = tileDepthCount.getTexturePlaceDepth() else {
                                // Больше мы ничего в текстуре разместить не можем
                                return nil
                            }
                            placeTiles.append(PlaceTile(metalTile: prevMetalTile, placeIn: tile, depth: depth))
                            // Нашли замену, выходим из цикла
                            return true
                        }
                    }
                    return false
                }
                
                // Ищем тайлы, которые частично покрывают необходимый
                func findPartialReplacement() -> Bool? {
                    var foundSome = false
                    for prev in savedTiles {
                        let prevMetalTile = prev.metalTile
                        let prevTile = prev.metalTile.tile
                        
                        // Предыдущий тайл частично покрывает наш необходимый тайл
                        if tile.covers(prevTile) {
                            // Добавляем его, и продолжаем искать другие тайлы, покрывающие текущий
                            guard let depth = tileDepthCount.getTexturePlaceDepth() else {
                                // Больше мы ничего в текстуре разместить не можем
                                return nil
                            }
                            placeTiles.append(PlaceTile(metalTile: prevMetalTile, placeIn: prevTile, depth: depth))
                            foundSome = true
                        }
                    }
                    return foundSome
                }
                
                // Заменяем тайл, которого еще нету на временный тайл с предыдущего кадра
                if metalTile == nil {
                    let zDiff = zoom - previousZoom
                    
                    var found: Bool? = false
                    if zDiff >= 0 {
                        // Мы увеличили зум карты, приблизили карту
                        // В этом случае у нас есть полностью покрывающий тайл с предыдущего кадра
                        found = findFullReplacement()
                        
                        // но если нету, то ищем внутренние тайлы необходимого тайла
                        if (found == false) { found = findPartialReplacement() }
                    } else {
                        // Мы уменьшили зум карты, отодвинули карту
                        // Ищем внутренние тайлы необходимого тайла
                        found = findPartialReplacement()
                    }
                    
                    if found == nil {
                        // В текстуре больше нету места
                        // Бесполезно искать замены
                        break
                    }
                    
                    // Для текущего тайла нашли замену (или нет)
                    // Идем к следующему необходимому тайлу
                    continue
                }
                
                guard let depth = tileDepthCount.getTexturePlaceDepth() else {
                    // В текстуре больше нету места для тайлов
                    break
                }
                
                // Нужный нам тайл готов, устанавливаем его
                placeTiles.append(PlaceTile(metalTile: metalTile!, placeIn: tile, depth: depth))
            }
            
            // Сохраняем текущие тайлы, чтобы заменять отсутствующие тайлы следующего кадра
            savedTiles = placeTiles
            previousZoom = zoom
            previousStorageHash = storageHash
            
            // Рисуем готовые тайлы в текстуре.
            // Размещаем их так, чтобы контролировать детализацию
            tilesTexture.activateEncoder(commandBuffer: commandBuffer, index: currentIndex)
            tilesTexture.selectTilePipeline()
            for i in savedTiles.indices {
                let placeTile = savedTiles[i]
                let depth = placeTile.depth
                let placed = tilesTexture.draw(placeTile: placeTile, depth: depth, maxDepth: 4)
                if placed == false {
                    print("[ERROR] No place for tile in texture!")
                    break
                }
            }
            
            // Рисуем координаты тайлов на самих тайлах для тестирование
            if false {
                let texts = tilesTexture.texts
                if texts.isEmpty == false {
                    let tilesTextVertices = textRenderer.collectMultiTextVertices(for: texts)
                    tileTextVerticesBuffer.contents().copyMemory(from: tilesTextVertices, byteCount: MemoryLayout<TextVertex>.stride * tilesTextVertices.count)
                    previousTilesTextKey = "\(texts.count)"
                    tileTextVerticesCount = tilesTextVertices.count
                    
                    var tilesTextColor = SIMD3<Float>(1, 0, 0)
                    var tilesProjection = Matrix.orthographicMatrix(left: 0, right: Float(4096), bottom: 0, top: Float(4096), near: -1, far: 1)
                    let tilesRenderEncoder = tilesTexture.renderEncoder!
                    tilesRenderEncoder.setScissorRect(MTLScissorRect(x: 0, y: 0, width: tilesTexture.size, height: tilesTexture.size))
                    tilesRenderEncoder.setRenderPipelineState(textRenderer.pipelineState)
                    tilesRenderEncoder.setVertexBuffer(tileTextVerticesBuffer, offset: 0, index: 0)
                    tilesRenderEncoder.setVertexBytes(&tilesProjection, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
                    tilesRenderEncoder.setFragmentTexture(textRenderer.texture, index: 0)
                    tilesRenderEncoder.setFragmentBytes(&tilesTextColor, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
                    tilesRenderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tileTextVerticesCount)
                }
            }
            
            // Завершаем рисование в текстуре с тайлами
            tilesTexture.endEncoding()
        }
        
        
        // Camera uniform
        var cameraUniform = CameraUniform(matrix: cameraMatrix)
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: clearColor.x,
                                                                            green: clearColor.y,
                                                                            blue: clearColor.z,
                                                                            alpha: clearColor.w)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        globePipeline.selectPipeline(renderEncoder: renderEncoder)
        
        renderEncoder.setCullMode(.front)
        
        renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBuffer(sphereVerticesBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&globe, length: MemoryLayout<Globe>.stride, index: 2)
        renderEncoder.setFragmentTexture(tilesTexture.texture[currentIndex], index: 0)
        
        var tileData = tilesTexture.tileData
        renderEncoder.setVertexBytes(&tileData, length: MemoryLayout<TilesTexture.TileData>.stride * tileData.count, index: 3)
        
        if tileData.isEmpty == false {
            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: sphereIndicesCount,
                                                indexType: .uint32,
                                                indexBuffer: sphereIndicesBuffer,
                                                indexBufferOffset: 0,
                                                instanceCount: tileData.count)
        }
        
        // Axes
        polygonPipeline.setPipelineState(renderEncoder: renderEncoder)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 6)
        
        for point in camera.testPoints {
            let verticesTest = [PolygonsPipeline.Vertex(position: point, color: SIMD4<Float>(0, 0, 0, 1))]
            renderEncoder.setVertexBytes(verticesTest, length: MemoryLayout<PolygonsPipeline.Vertex>.stride * verticesTest.count, index: 0)
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: verticesTest.count)
        }
        camera.testPoints = []
        
        let zoomText = TextEntry(text: "z: " + cameraControl.zoom.formatted(.number.precision(.fractionLength(2))),
                                 position: SIMD2<Float>(100, Float(screenMatrixSize.height) - 300),
                                 scale: 100)
        let textVertices = textRenderer.collectMultiTextVertices(for: [
            zoomText
        ])
        
        var zoomTextColor = SIMD3<Float>(0, 0, 0)
        renderEncoder.setRenderPipelineState(textRenderer.pipelineState)
        renderEncoder.setVertexBytes(textVertices, length: MemoryLayout<TextVertex>.stride * textVertices.count, index: 0)
        renderEncoder.setVertexBytes(&screenMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        renderEncoder.setFragmentTexture(textRenderer.texture, index: 0)
        renderEncoder.setFragmentBytes(&zoomTextColor, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: textVertices.count)
        
        renderEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.semaphore.signal()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private struct TileXY {
        let tileX: Int
        let tileY: Int
    }
    
    private struct Center {
        let tileX: Double
        let tileY: Double
    }
    
    private func getCenter(targetZoom: Int) -> Center {
        let pan = cameraControl.pan
        let tileX = -(pan.x - 1.0) / 2.0 * Double(1 << targetZoom)
        
        let latitude = pan.y * maxLatitude
        let yMerc = log(tan(Double.pi / 4.0 + latitude / 2.0))
        let yNormalized = (Double.pi - yMerc) / (2.0 * Double.pi)
        let tileY = yNormalized * Double(1 << targetZoom)
        
        return Center(tileX: tileX, tileY: tileY)
    }
    
    private func iSeeTiles(globe: Globe, targetZoom: Int, center: Center) -> Set<Tile> {
        let tileX = (Int) (center.tileX)
        let tileY = (Int) (center.tileY)
        
        print("[CENTER] \(tileX), \(tileY), \(targetZoom)")
        let rotation = camera.createRotationMatrix(globe: globe)
        var result: Set<Tile> = []
        camera.collectVisibleTiles(x: 0, y: 0, z: 0, targetZ: targetZoom, radius: globe.radius, rotation: rotation, result: &result,
                                   centerTile: Tile(x: tileX, y: tileY, z: targetZoom)
        )
        
        // Удаляем все дубликаты из результата
        return result
    }
}
