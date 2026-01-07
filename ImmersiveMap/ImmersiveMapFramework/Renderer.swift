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
    let parameters: Parameters
    let polygonPipeline: PolygonsPipeline
    let tilePipeline: TilePipeline
    let globePipeline: GlobePipeline
    let camera: Camera
    let cameraControl: CameraControl
    let tileCulling: TileCulling
    var transition: Float = 0
    var screenPoints = ScreenPoints()
    
    private var metalTilesStorage: MetalTilesStorage?
    private let tilesTexture: TilesTexture
    private let textRenderer: TextRenderer
    private let uiView: ImmersiveMapUIView
    private let debugOverlayRenderer: DebugOverlayRenderer
    
    private let baseGridBuffers: GridBuffers
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
    private var viewMode: ViewMode = ViewMode.spherical
    private var radius: Double = 0.0
    private let screenMatrix: ScreenMatrix = ScreenMatrix()
    private let labelScreenCompute: LabelScreenCompute
    private let labelCache: LabelCache
    private let flatTileOriginCalculator: FlatTileOriginCalculator
    
    private var tileTextVerticesBuffer: MTLBuffer
    private var previousTilesTextKey: String = ""
    private var tileTextVerticesCount: Int = 0
    private let labelFadeDuration: Float = 0.25
    
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
        
        let bundle = Bundle(for: Renderer.self)
        let library = try! metalDevice.makeDefaultLibrary(bundle: bundle)
        
        polygonPipeline = PolygonsPipeline(metalDevice: metalDevice, layer: layer, library: library)
        tilePipeline = TilePipeline(metalDevice: metalDevice, layer: layer, library: library)
        globePipeline = GlobePipeline(metalDevice: metalDevice, layer: layer, library: library)
        let globeComputePipeline = GlobeLabelComputePipeline(metalDevice: metalDevice, library: library)
        let flatComputePipeline = FlatLabelComputePipeline(metalDevice: metalDevice, library: library)
        let labelCollisionPipeline = LabelCollisionPipeline(metalDevice: metalDevice, library: library)
        let labelCollisionCalculator = LabelCollisionCalculator(pipeline: labelCollisionPipeline, metalDevice: metalDevice)
        labelScreenCompute = LabelScreenCompute(globeComputePipeline: globeComputePipeline,
                                                flatComputePipeline: flatComputePipeline,
                                                labelCollisionCalculator: labelCollisionCalculator,
                                                metalDevice: metalDevice)
        
        textRenderer = TextRenderer(device: metalDevice, library: library)
        tilesTexture = TilesTexture(metalDevice: metalDevice, tilePipeline: tilePipeline)
        debugOverlayRenderer = DebugOverlayRenderer(metalDevice: metalDevice)
        camera = Camera()
        tileCulling = TileCulling(camera: camera)
        cameraControl = CameraControl()
        //cameraControl.setZoom(zoom: 6)
        //cameraControl.setLatLonDeg(latDeg: 55.751244, lonDeg: 37.618423)
        previousZoom = Int(cameraControl.zoom)
        
        let baseGrid = SphereGeometry.createGrid(stacks: 30, slices: 30)
        baseGridBuffers = GridBuffers(
            verticesBuffer: metalDevice.makeBuffer(
                bytes: baseGrid.vertices,
                length: MemoryLayout<SphereGeometry.Vertex>.stride * baseGrid.vertices.count
            )!,
            indicesBuffer: metalDevice.makeBuffer(
                bytes: baseGrid.indices,
                length: MemoryLayout<UInt32>.stride * baseGrid.indices.count
            )!,
            indicesCount: baseGrid.indices.count
        )
        
        let len = MemoryLayout<TextVertex>.stride * 4000
        tileTextVerticesBuffer = metalDevice.makeBuffer(length: len)!
        flatTileOriginCalculator = FlatTileOriginCalculator(metalDevice: metalDevice)
        
        
        labelCache = LabelCache(metalDevice: metalDevice, computeGlobeToScreen: labelScreenCompute)
        metalTilesStorage = MetalTilesStorage(mapStyle: DefaultMapStyle(),
                                              metalDevice: metalDevice,
                                              renderer: self,
                                              textRenderer: textRenderer)
    }
        
    func newTileAvailable(tile: Tile) {
        uiView.redraw = true
    }
    
    func render(to layer: CAMetalLayer) {
        semaphore.wait()
        
        let drawSize = layer.drawableSize
        if drawSize.width == 0 || drawSize.height == 0 {
            return
        }
        
        // При изменении размера экрана пересчитываем матрицы вида.
        if drawSize != lastDrawableSize {
            let aspect = Float(drawSize.width) / Float(drawSize.height)
            camera.recalculateProjection(aspect: aspect)
            lastDrawableSize = drawSize
        }
        
        // Экранная матрица для размещения 2д элементов на экране
        screenMatrix.update(drawSize)
        
        // Без экранной матрицы не можем продолжить рендринг
        guard var screenMatrix = screenMatrix.get() else {
            return
        }
        
        
        // Не используем tripple buffering
        // На моем телефоне и без него хорошо работает
        let nextIndex = (currentIndex + 1) % 3
        currentIndex = nextIndex
        currentIndex = 0
        
        // Движение камеры
        CameraUpdater.updateIfNeeded(camera: camera, cameraControl: cameraControl)
        
        guard let cameraMatrix = camera.cameraMatrix,
              let drawable = layer.nextDrawable() else {
            semaphore.signal()
            return
        }
        
        let clearColor = parameters.clearColor
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        let viewResult = ViewModeCalculator.calculate(zoom: cameraControl.zoom,
                                                      globePan: cameraControl.globePan)
        transition = viewResult.transition
        radius = viewResult.radius
        let mapSize = viewResult.mapSize
        var globe = viewResult.globe
        let newViewMode = viewResult.viewMode
        
        if viewMode != newViewMode {
            // Необходимо переключение режима
            switchRenderMode()
        }
        
        // Получаем текущий центральный тайл
        let zoom = Int(cameraControl.zoom)
        var center: Center = Center(tileX: 0, tileY: 0)
        
        
        // Тайлы, которые пользователь видит в полностью подгруженном состоянии
        // они там могут быть в разнобой, просто все тайлы, которые пользователь видит
        var seeTiles: Set<Tile> = Set()
        if viewMode == .spherical {
            center = getGlobeMapCenter(targetZoom: zoom)
            seeTiles = tileCulling.iSeeTilesGlobe(globe: globe, targetZoom: zoom, center: center, viewMode: viewMode,
                                                  pan: SIMD2<Float>(Float(cameraControl.globePan.x), Float(cameraControl.globePan.y)))
        } else if viewMode == .flat {
            center = getFlatMapCenter(targetZoom: zoom)
            print("Center = \(center)")
            seeTiles = tileCulling.iSeeTilesFlat(targetZoom: zoom, center: center, pan: cameraControl.flatPan, mapSize: mapSize)
        }
        let seeTilesHash = seeTiles.hashValue
        
        // Если мы видим такие же тайлы, что и на предыдущем кадре, то тогда нету смысла обрабатывать их опять
        // Использовать тайлы с предыдущего кадра
        if previousSeeTilesHash != seeTilesHash {
            print("Previous see tiles hash changed")
            // Сортируем тайлы для правильной, последовательной отрисовки
            savedSeeTiles = TileSorter.sortForRendering(seeTiles, center: center)
            previousSeeTilesHash = seeTilesHash
        }
        
        print("- - -")
        print("count = \(savedSeeTiles.count)")
        for i in 0..<savedSeeTiles.count {
            let sortedSeeTile = savedSeeTiles[i]
            print("\(i+1)) x=\(sortedSeeTile.x), y=\(sortedSeeTile.y), z=\(sortedSeeTile.z), loop=\(sortedSeeTile.loop)")
        }
        
        
        // Запрашиваем тайлы, которые нужны для отрисовки карты
        // Тайлы, которых нету будут запрошены по интернету и так же будет попытка локальной загрузки с диска
        var storageHash = Int(0)
        let tilesFromStorage = metalTilesStorage!.request(tiles: savedSeeTiles, hash: &storageHash)
        
        
        // Перерисовываем только если загруженные тайлы другие
        if previousStorageHash != storageHash {
            print("Tiles storage hash changed")
            // Если тайлы изменились
            // Заменяем пробелы тайлами из предыдущего кадра.
            let placeTiles = getPlaceTiles(tilesFromStorage: tilesFromStorage, zoom: zoom)
            // Сохраняем текущие тайлы, чтобы заменять отсутствующие тайлы следующего кадра
            savedTiles = placeTiles
            previousZoom = zoom
            previousStorageHash = storageHash
            
            
            if viewMode == .spherical {
                // Рисуем готовые тайлы в текстуре.
                // Размещаем их так, чтобы контролировать детализацию
                tilesTexture.activateEncoder(commandBuffer: commandBuffer, index: currentIndex)
                drawGlobeTexture()
                
                // Рисуем координаты тайлов как текст на самих тайлах для тестирование
                drawTileCoordText()
                
                // Завершаем рисование в текстуре с тайлами
                tilesTexture.endEncoding()
            }
            
        }

        let nowTime = Date().timeIntervalSince(startDate)
        labelCache.update(placeTiles: savedTiles, now: nowTime)
        var tileOriginDataBuffer: MTLBuffer?
        if viewMode == .flat {
            // рассчитываем сдвиг по тайлам с Double точностью для последующей отрисовки текстовых меток
            tileOriginDataBuffer = flatTileOriginCalculator.update(tiles: labelCache.labelTilesList,
                                                                   flatPan: cameraControl.flatPan,
                                                                   mapSize: mapSize)
        }
        
        
        // Camera uniform
        var cameraUniform = CameraUniform(matrix: cameraMatrix,
                                          eye: camera.eye,
                                          padding: 0)


        // Высчитываем положения и коллизии текстовых меток
        if viewMode == .spherical {
            labelScreenCompute.runGlobe(drawSize: drawSize,
                                           cameraUniform: cameraUniform,
                                           globe: globe,
                                           commandBuffer: commandBuffer,
                                           labelRuntimeBuffer: labelCache.labelRuntimeBuffer,
                                           now: Float(nowTime),
                                           duration: labelFadeDuration)
        } else if viewMode == .flat {
            if let tileOriginDataBuffer {
                labelScreenCompute.runFlat(drawSize: drawSize,
                                              cameraUniform: cameraUniform,
                                              tileOriginDataBuffer: tileOriginDataBuffer,
                                              commandBuffer: commandBuffer,
                                              labelRuntimeBuffer: labelCache.labelRuntimeBuffer,
                                              now: Float(nowTime),
                                              duration: labelFadeDuration)
            }
        }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: clearColor.x,
                                                                            green: clearColor.y,
                                                                            blue: clearColor.z,
                                                                            alpha: clearColor.w)
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        if viewMode == .spherical {
            globePipeline.selectPipeline(renderEncoder: renderEncoder)
            
            renderEncoder.setCullMode(.front)
            renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
            renderEncoder.setVertexBytes(&globe, length: MemoryLayout<Globe>.stride, index: 2)
            renderEncoder.setFragmentTexture(tilesTexture.texture[currentIndex], index: 0)
            renderEncoder.setVertexBuffer(baseGridBuffers.verticesBuffer, offset: 0, index: 0)
            
            let tileMappings = tilesTexture.tileData
            if tileMappings.isEmpty == false {
                for mapping in tileMappings {
                    var toMapping = mapping
                    renderEncoder.setVertexBytes(&toMapping, length: MemoryLayout<TilesTexture.TileData>.stride, index: 3)
                    
                    renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                        indexCount: baseGridBuffers.indicesCount,
                                                        indexType: .uint32,
                                                        indexBuffer: baseGridBuffers.indicesBuffer,
                                                        indexBufferOffset: 0)
                }
            }
            
        } else if viewMode == .flat {
            tilePipeline.selectPipeline(renderEncoder: renderEncoder)
            renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
            
            let flatPan = cameraControl.flatPan
            for placeTile in savedTiles {
                let metalTile = placeTile.metalTile
                let tile = metalTile.tile
                let buffers = metalTile.tileBuffers
                let placeIn = placeTile.placeIn
                
                let mapSize = 2.0 * Double.pi * radius
                let halfMapSize = mapSize / 2.0
                
                renderEncoder.setVertexBuffer(buffers.verticesBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(buffers.stylesBuffer, offset: 0, index: 2)
                
                let tilesCount = 1 << tile.z
                let tileSize = mapSize / Double(tilesCount)
                let scale = tileSize / 4096.0
                
                var modelMatrix = Matrix.translationMatrix(
                    x: Float(Double(tile.x) * tileSize - halfMapSize + flatPan.x * halfMapSize) + Float(placeIn.loop) * Float(mapSize),
                    y: Float(Double(tilesCount - tile.y - 1) * tileSize - halfMapSize - flatPan.y * halfMapSize),
                    z: 0
                ) * Matrix.scaleMatrix(sx: Float(scale), sy: Float(scale), sz: 1)
                renderEncoder.setVertexBytes(&modelMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 3)
                
                renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                    indexCount: buffers.indicesCount,
                                                    indexType: .uint32,
                                                    indexBuffer: buffers.indicesBuffer,
                                                    indexBufferOffset: 0)
            }
        }
        
        
        // Draw labels
        renderEncoder.setRenderPipelineState(textRenderer.labelPipelineState)
        var color = SIMD3<Float>(1.0, 0.0, 0.0)
        var globalTextShift: simd_int1 = 0
        let screenPositions = labelScreenCompute.labelOutputBuffer
        let labelInputsBuffer = labelScreenCompute.labelInputBuffer
        let collisionOutput = labelScreenCompute.labelCollisionOutputBuffer
        let labelRuntimeBuffer = labelCache.labelRuntimeBuffer
        var appTime = Float(nowTime)
        renderEncoder.setVertexBytes(&screenMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        renderEncoder.setVertexBuffer(screenPositions, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(labelInputsBuffer, offset: 0, index: 4)
        renderEncoder.setVertexBuffer(collisionOutput, offset: 0, index: 5)
        renderEncoder.setVertexBuffer(labelRuntimeBuffer, offset: 0, index: 6)
        renderEncoder.setVertexBytes(&appTime, length: MemoryLayout<Float>.stride, index: 7)
        renderEncoder.setFragmentTexture(textRenderer.texture, index: 0)
        renderEncoder.setFragmentBytes(&color, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        for drawLabel in labelCache.drawLabels {
            let textVerticesBuffer = drawLabel.labelsVerticesBuffer
            let labelsCount = drawLabel.labelsCount
            let textVerticesCount = drawLabel.labelsVerticesCount
            
            if labelsCount > 0 {
                renderEncoder.setVertexBuffer(textVerticesBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBytes(&globalTextShift, length: MemoryLayout<simd_int1>.stride, index: 3)
                renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: textVerticesCount)
            }
            
            globalTextShift += simd_int1(labelsCount)
        }

        
        
        debugOverlayRenderer.drawAxes(renderEncoder: renderEncoder,
                                      polygonPipeline: polygonPipeline,
                                      cameraUniform: cameraUniform)
        
        for point in camera.testPoints {
            let verticesTest = [PolygonsPipeline.Vertex(position: point, color: SIMD4<Float>(1, 0, 0, 1))]
            renderEncoder.setVertexBytes(verticesTest,
                                         length: MemoryLayout<PolygonsPipeline.Vertex>.stride * verticesTest.count,
                                         index: 0)
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: verticesTest.count)
        }
        camera.testPoints = []
        
        renderEncoder.setVertexBytes(&screenMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        for screenPoint in screenPoints.get() {
            let simd4 = SIMD4<Float>(screenPoint.x, screenPoint.y, 0, 1)
            let verticesTest = [PolygonsPipeline.Vertex(position: simd4, color: SIMD4<Float>(1, 0, 0, 1))]
            let len = MemoryLayout<PolygonsPipeline.Vertex>.stride * verticesTest.count
            renderEncoder.setVertexBytes(verticesTest, length: len, index: 0)
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: verticesTest.count)
        }
        
        debugOverlayRenderer.drawZoomText(renderEncoder: renderEncoder,
                                          textRenderer: textRenderer,
                                          screenMatrix: screenMatrix,
                                          drawSize: drawSize,
                                          zoom: cameraControl.zoom)
        
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
    
    private func getGlobeMapCenter(targetZoom: Int) -> Center {
        let pan = cameraControl.globePan
        let tileX = -(pan.x - 1.0) / 2.0 * Double(1 << targetZoom)
        
        let latitude = pan.y * maxLatitude
        let yMerc = log(tan(Double.pi / 4.0 + latitude / 2.0))
        let yNormalized = (Double.pi - yMerc) / (2.0 * Double.pi)
        let tileY = yNormalized * Double(1 << targetZoom)
        
        return Center(tileX: tileX, tileY: tileY)
    }
    
    private func getFlatMapCenter(targetZoom: Int) -> Center {
        let pan = cameraControl.flatPan
        
        let tilesCount = 1 << targetZoom
        let tileX = ((-pan.x + 1.0) / 2.0) * Double(tilesCount)
        let tileY = ((-pan.y + 1.0) / 2.0) * Double(tilesCount)
        return Center(tileX: tileX, tileY: tileY)
    }

    
    func switchRenderMode() {
        let globePan = cameraControl.globePan
        let flatPan = cameraControl.flatPan
        
        if viewMode == .flat {
            let globeLat = 2.0 * atan(exp(flatPan.y * Double.pi)) - (Double.pi * 0.5)
            let yNormalaized = globeLat / maxLatitude
            cameraControl.globePan = SIMD2<Double>(flatPan.x,  yNormalaized)
            viewMode = .spherical
        } else if viewMode == .spherical {
            let globeLat = globePan.y * maxLatitude
            let yMerc = log(tan(Double.pi / 4.0 + globeLat / 2.0))
            let yNormalized = yMerc / Double.pi
            
            cameraControl.flatPan = SIMD2<Double>(globePan.x,  yNormalized)
            viewMode = .flat
        }
    }
    
    
    private func getPlaceTiles(tilesFromStorage: [MetalTilesStorage.TileInStorage], zoom: Int) -> [PlaceTile] {
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
        
        return placeTiles
    }
    
    private func drawTileCoordText() {
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
    }
    
    private func drawGlobeTexture() {
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
    }
}
