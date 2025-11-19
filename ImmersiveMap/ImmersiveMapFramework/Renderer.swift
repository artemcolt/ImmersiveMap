//
//  Renderer.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import simd
import Metal
import MetalKit
import QuartzCore // Для CAMetalLayer

class Renderer {
    struct Globe {
        let xRotation: Float
        let yRotation: Float
        let radius: Float
    }
    
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
    
    private var previousTiles: [PlaceTile] = []
    private var previousZoom: Int
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
        cameraControl.setZoom(zoom: 2)
        cameraControl.setLatLonDeg(latDeg: 55.751244, lonDeg: 37.618423)
        previousZoom = Int(cameraControl.zoom)
        
        let sphereGeometry = SphereGeometry(stacks: 128, slices: 128)
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
        let currentDrawableSize = layer.drawableSize
        
        if screenMatrixSize != currentDrawableSize {
            screenMatrixSize = currentDrawableSize
            screenMatrix = Matrix.orthographicMatrix(left: 0, right: Float(screenMatrixSize.width),
                                                     bottom: 0, top: Float(screenMatrixSize.height),
                                                     near: -1, far: 1)
        }
        
        guard var screenMatrix = screenMatrix else {
            return
        }
        
        if currentDrawableSize.width == 0 || currentDrawableSize.height == 0 {
            return
        }
        
        semaphore.wait()
        
        if currentDrawableSize != lastDrawableSize {
            let aspect = Float(currentDrawableSize.width) / Float(currentDrawableSize.height)
            camera.recalculateProjection(aspect: aspect)
            lastDrawableSize = currentDrawableSize
        }
        
        let nextIndex = (currentIndex + 1) % 3
        currentIndex = nextIndex
        currentIndex = 0
        
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
//            camera.center = SIMD3<Float>(Float(cameraControl.pan.x), 0, 0)
            
            camera.recalculateMatrix()
            cameraControl.update = false
        }
        let worldScale = pow(2.0, floor(cameraControl.zoom))
        
        guard let cameraMatrix = camera.cameraMatrix,
              let drawable = layer.nextDrawable() else {
            semaphore.signal()
            return
        }
        
        let clearColor = parameters.clearColor
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        var globe = Globe(xRotation: Float(cameraControl.pan.y) * Float(maxLatitude),
                          yRotation: Float(cameraControl.pan.x) * Float.pi,
                          radius: 0.14 * worldScale)
        
        
        let zoom = Int(cameraControl.zoom)
        let center = getCenter(targetZoom: zoom)
        
        // Тайлы, которые пользователь видит в полностью подгруженном состоянии
        // они там могут быть в разнобой, просто все тайлы, которые пользователь видит
        let seeTiles = iSeeTiles(globe: globe, targetZoom: zoom, center: center).sorted(by: { t1, t2 in
            if t1.z != t2.z {
                return t1.z > t2.z
            }
            
            let dx1 = abs(t1.x - Int(center.tileX))
            let dy1 = abs(t1.y - Int(center.tileY))
            let maxD1 = max(dx1, dy1)
            
            let dx2 = abs(t2.x - Int(center.tileX))
            let dy2 = abs(t2.y - Int(center.tileY))
            let maxD2 = max(dx2, dy2)
            
            return maxD1 < maxD2 // true -> элементы остаются на месте
        })
        
        print("- - -")
        seeTiles.forEach { t in
            print(t)
        }
        
        // depth = 0 -> покрыть всю текстуру. Вместимость: 0 тайлов
        // depth = 1 -> покрыть 1/4 текстуры. Вместимость: 1 тайл
        // depth = 2 -> покрыть 1/8 текстуры.
        // depth = 3 -> покрыть 1/16 текстуры
        
        var depth1Count = 0
        var depth2Count = 0
        var depth3Count = 0
        var depth4Count = 0
        
        let depth1Capacity = 1
        let depth2Capacity = 8
        let depth3Capacity = 5
        let depth4Capacity = 16 + 28
        
        func countTexturePlaces() {
            if depth1Count < depth1Capacity {
                depths.append(1)
                depth1Count += 1
            } else if depth2Count < depth2Capacity {
                depths.append(2)
                depth2Count += 1
            } else if depth3Count < depth3Capacity {
                depths.append(3)
                depth3Count += 1
            } else if depth4Count < depth4Capacity {
                depths.append(4)
                depth4Count += 1
            }
        }
        
        var placeTiles: [PlaceTile] = []
        var depths: [UInt8] = []
        
        // Запрашиваем тайлы, которые нужны для отрисовки карты
        // Тайлы, которых нету будут запрошены по интернету и так же будет попытка локальной загрузки с диска
        let tilesFromStorage = metalTilesStorage!.request(tiles: seeTiles)
        
        if (zoom == 0) {
            print("asd")
        }
        
        // Заменяем пробелы тайлами из предыдущего кадра.
        for i in 0..<tilesFromStorage.count {
            let storageTile = tilesFromStorage[i]
            let metalTile = storageTile.metalTile
            let tile = storageTile.tile
            
            func findFullReplacement() -> Bool {
                for prev in previousTiles {
                    let prevMetalTile = prev.metalTile
                    let prevTile = prev.metalTile.tile
                    
                    // Предыдущий тайл полностью покрывает наш необходимый тайл
                    if prevTile.covers(tile) {
                        placeTiles.append(PlaceTile(metalTile: prevMetalTile, placeIn: tile))
                        countTexturePlaces()
                        // Нашли замену, выходим из цикла
                        return true
                    }
                }
                return false
            }
            
            func findPartialReplacement() {
                for prev in previousTiles {
                    let prevMetalTile = prev.metalTile
                    let prevTile = prev.metalTile.tile
                    
                    // Предыдущий тайл частично покрывает наш необходимый тайл
                    if tile.covers(prevTile) {
                        // Добавляем его, и продолжаем искать другие тайлы, покрывающие текущий
                        placeTiles.append(PlaceTile(metalTile: prevMetalTile, placeIn: prevTile))
                        countTexturePlaces()
                    }
                }
            }
            
            // Заменяем тайл, которого еще нету на временный тайл с предыдущего кадра
            if metalTile == nil {
                let zDiff = zoom - previousZoom
                
                if zDiff >= 0 {
                    let found = findFullReplacement()
                    if (found == false) { findPartialReplacement() }
                } else {
                    findPartialReplacement()
                }
                
                // Для текущего тайла нашли замену (или нет)
                // Идем к следующему необходимому тайлу
                continue
            }
            
            // Нужный нам тайл готов, устанавливаем его
            placeTiles.append(PlaceTile(metalTile: metalTile!, placeIn: tile))
            countTexturePlaces()
        }
        
        // Сохраняем текущие тайлы, чтобы заменять отсутствующие тайлы следующего кадра
        previousTiles = placeTiles
        previousZoom = zoom
            
        
        // Рисуем готовые тайлы в текстуре.
        // Размещаем их так, чтобы контролировать детализацию
        tilesTexture.activateEncoder(commandBuffer: commandBuffer, index: currentIndex)
        tilesTexture.selectTilePipeline()
        for i in placeTiles.indices {
            if depths.count <= i {
                print("[ERROR] No place for tile in texture!")
                break
            }
            let placeTile = placeTiles[i]
            let depth = depths[i]
            let placed = tilesTexture.draw(placeTile: placeTile, depth: depth, maxDepth: 4)
            if placed == false {
                print("[ERROR] No place for tile in texture!")
                break
            }
        }
        
        // Рисуем координаты тайлов на самих тайлах для тестирование
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
        
        // Завершаем рисование в текстуре с тайлами
        tilesTexture.endEncoding()
        
        
        
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
        //renderPassDescriptor.colorAttachments[0].resolveTexture = drawable.texture
        
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
            
//            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: sphereIndicesCount, indexType: .uint32, indexBuffer: sphereIndicesBuffer, indexBufferOffset: 0)
        }
        
        // axes
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
    
    private func iSeeTiles(globe: Renderer.Globe, targetZoom: Int, center: Center) -> [Tile] {
        let tileX = (Int) (center.tileX)
        let tileY = (Int) (center.tileY)
        
        print("[CENTER] \(tileX), \(tileY), \(targetZoom)")
        let rotation = camera.createRotationMatrix(globe: globe)
        var result: [Tile] = []
        camera.collectVisibleTiles(x: 0, y: 0, z: 0, targetZ: targetZoom, radius: globe.radius, rotation: rotation, result: &result,
                                   centerTile: Tile(x: tileX, y: tileY, z: targetZoom)
        )
        
        // удаляем все дубликаты из результата
        return Array(Set(result))
    }
    
    struct PlaceTile {
        let metalTile: MetalTile
        let placeIn: Tile
        
        func isReplacement() -> Bool {
            return metalTile.tile != placeIn
        }
    }
}
