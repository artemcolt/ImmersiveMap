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
    let config: MapConfiguration
    let polygonPipeline: PolygonsPipeline
    let tilePipeline: TilePipeline
    let globePipeline: GlobePipeline
    private let screenPointDebugPipeline: ScreenPointDebugPipeline
    let globeCapRenderer: GlobeCapRenderer
    let starfield: Starfield
    let camera: Camera
    let cameraControl: CameraControl
    let tileCulling: TileCulling
    var transition: Float = 0
    var screenPoints = ScreenPoints()
    
    private var metalTilesStorage: MetalTilesStorage?
    private let tilesTexture: TilesTexture
    let textRenderer: TextRenderer
    private let uiView: ImmersiveMapUIView
    let debugOverlayRenderer: DebugOverlayRenderer
    
    private let baseGridBuffers: GridBuffers
    private var lastDrawableSize: CGSize = .zero
    private let maxLatitude = 2.0 * atan(exp(Double.pi)) - Double.pi / 2.0
    
    private let semaphore = DispatchSemaphore(value: 3)
    private var currentIndex = 0
    
    private let startDate = Date()
    private var previousSeeTilesHash: Int = 0
    private var savedSeeTiles: [Tile] = []
    private var placeTilesContext = PlaceTilesContext.empty
    private var previousZoom: Int
    private var previousStorageHash: Int = 0
    private let tile: Tile = Tile(x: 0, y: 0, z: 0)
    private var viewMode: ViewMode = ViewMode.spherical
    private var radius: Double = 0.0
    private let screenMatrix: ScreenMatrix = ScreenMatrix()
    private let tilePointScreenCompute: TilePointScreenCompute
    private let roadPathScreenCompute: TilePointScreenCompute
    private let labelCache: LabelCache
    private let flatTileOriginCalculator: FlatTileOriginCalculator
    private let screenCollisionCalculator: ScreenCollisionCalculator
    private let labelStateUpdateCalculator: LabelStateUpdateCalculator
    private let roadLabelPlacementCalculator: RoadLabelPlacementCalculator
    private let roadLabelCollisionCalculator: RoadLabelCollisionCalculator
    private let roadLabelVisibilityCalculator: RoadLabelVisibilityCalculator
    private let tileRetentionTracker: TileRetentionTracker
    private var trackedTiles: [TileRetentionTracker.TrackedTile] = []
    private var previousTrackedTilesHash: Int = 0
    private var previousRoadLabelZoomBucket: Int = -1
    private var previousRoadLabelTileUnitsPerPixel: Float = 0.0
    
    private var tileTextVerticesBuffer: MTLBuffer
    private var previousTilesTextKey: String = ""
    private var tileTextVerticesCount: Int = 0
    private let labelFadeDuration: Float = 0.25
    
    init(layer: CAMetalLayer, uiView: ImmersiveMapUIView, config: MapConfiguration = .default) {
        self.metalLayer = layer
        self.uiView = uiView
        self.config = config
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
        let library: MTLLibrary
        do {
            library = try metalDevice.makeDefaultLibrary(bundle: bundle)
        } catch {
            if let fallback = metalDevice.makeDefaultLibrary() {
                library = fallback
            } else {
                fatalError("Не удалось создать MTLLibrary: \(error)")
            }
        }
        
        let mapStyle = DefaultMapStyle()
        let mapBaseColors = mapStyle.getMapBaseColors()
        
        polygonPipeline = PolygonsPipeline(metalDevice: metalDevice, layer: layer, library: library)
        tilePipeline = TilePipeline(metalDevice: metalDevice, layer: layer, library: library)
        globePipeline = GlobePipeline(metalDevice: metalDevice, layer: layer, library: library)
        screenPointDebugPipeline = ScreenPointDebugPipeline(metalDevice: metalDevice, layer: layer, library: library)
        starfield = Starfield(metalDevice: metalDevice,
                              layer: layer,
                              library: library,
                              config: config.starfield,
                              comets: config.comets)
        let globeComputePipeline = GlobeTilePointComputePipeline(metalDevice: metalDevice, library: library)
        let flatComputePipeline = FlatTilePointComputePipeline(metalDevice: metalDevice, library: library)
        let screenCollisionPipeline = ScreenCollisionPipeline(metalDevice: metalDevice, library: library)
        self.screenCollisionCalculator = ScreenCollisionCalculator(pipeline: screenCollisionPipeline,
                                                                    metalDevice: metalDevice)
        let labelStateUpdatePipeline = LabelStateUpdatePipeline(metalDevice: metalDevice, library: library)
        self.labelStateUpdateCalculator = LabelStateUpdateCalculator(pipeline: labelStateUpdatePipeline)
        let roadLabelPlacementPipeline = RoadLabelPlacementPipeline(metalDevice: metalDevice, library: library)
        self.roadLabelPlacementCalculator = RoadLabelPlacementCalculator(pipeline: roadLabelPlacementPipeline)
        let roadLabelCollisionPipeline = RoadLabelCollisionPipeline(metalDevice: metalDevice, library: library)
        self.roadLabelCollisionCalculator = RoadLabelCollisionCalculator(pipeline: roadLabelCollisionPipeline,
                                                                          metalDevice: metalDevice)
        let roadLabelVisibilityPipeline = RoadLabelVisibilityPipeline(metalDevice: metalDevice, library: library)
        self.roadLabelVisibilityCalculator = RoadLabelVisibilityCalculator(pipeline: roadLabelVisibilityPipeline,
                                                                           metalDevice: metalDevice)
        tilePointScreenCompute = TilePointScreenCompute(globeComputePipeline: globeComputePipeline,
                                                        flatComputePipeline: flatComputePipeline,
                                                        metalDevice: metalDevice)
        roadPathScreenCompute = TilePointScreenCompute(globeComputePipeline: globeComputePipeline,
                                                       flatComputePipeline: flatComputePipeline,
                                                       metalDevice: metalDevice)
        
        textRenderer = TextRenderer(device: metalDevice, library: library)
        tilesTexture = TilesTexture(metalDevice: metalDevice, tilePipeline: tilePipeline)
        debugOverlayRenderer = DebugOverlayRenderer(metalDevice: metalDevice)
        camera = Camera()
        tileCulling = TileCulling(camera: camera, debugLogging: config.debugRenderLogging)
        cameraControl = CameraControl(config: config)
        cameraControl.setZoom(zoom: 13)
        cameraControl.setLatLonDeg(latDeg: 55.751244, lonDeg: 37.618423)
        previousZoom = Int(cameraControl.zoom)
        
        let baseGrid = SphereGeometry.createGrid(stacks: 50, slices: 50)
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

        globeCapRenderer = GlobeCapRenderer(metalDevice: metalDevice,
                                            layer: layer,
                                            library: library,
                                            maxLatitude: maxLatitude,
                                            mapBaseColors: mapBaseColors)

        labelCache = LabelCache(metalDevice: metalDevice, screenCompute: tilePointScreenCompute)
        tileRetentionTracker = TileRetentionTracker(holdSeconds: config.tileHoldSeconds)
        metalTilesStorage = MetalTilesStorage(mapStyle: mapStyle,
                                              metalDevice: metalDevice,
                                              renderer: self,
                                              textRenderer: textRenderer,
                                              config: config)
    }
        
    func newTileAvailable(tile: Tile) {
        uiView.redraw = true
    }
    
    func render(to layer: CAMetalLayer) {
        semaphore.wait()
        var didSchedule = false
        defer {
            if !didSchedule {
                semaphore.signal()
            }
        }
        
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
        currentIndex = 0
        
        // Движение камеры
        CameraUpdater.updateIfNeeded(camera: camera, cameraControl: cameraControl)
        
        guard let cameraMatrix = camera.cameraMatrix,
              let cameraView = camera.view,
              let drawable = layer.nextDrawable() else {
            return
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        // Какой режим рендринга сейчас (глобус или плоскость)
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
            seeTiles = tileCulling.iSeeTilesFlat(targetZoom: zoom, center: center, pan: cameraControl.flatPan, mapSize: mapSize)
        }
        let seeTilesHash = seeTiles.hashValue
        if config.debugRenderLogging {
            print("Center = \(center)")
        }
        
        // Если мы видим такие же тайлы, что и на предыдущем кадре, то тогда нету смысла обрабатывать их опять
        // Использовать тайлы с предыдущего кадра
        if previousSeeTilesHash != seeTilesHash {
            if config.debugRenderLogging {
                print("Previous see tiles hash changed")
            }
            // Сортируем тайлы для правильной, последовательной отрисовки
            savedSeeTiles = TileSorter.sortForRendering(seeTiles, center: center)
            previousSeeTilesHash = seeTilesHash
        }
        
        if config.debugRenderLogging {
            print("- - -")
            print("count = \(savedSeeTiles.count)")
            for i in 0..<savedSeeTiles.count {
                let sortedSeeTile = savedSeeTiles[i]
                print("\(i+1)) x=\(sortedSeeTile.x), y=\(sortedSeeTile.y), z=\(sortedSeeTile.z), loop=\(sortedSeeTile.loop)")
            }
        }
        
        
        // Запрашиваем тайлы, которые нужны для отрисовки карты
        // Тайлы, которых нету будут запрошены по интернету и так же будет попытка локальной загрузки с диска
        var storageHash = Int(0)
        let tilesFromStorage = metalTilesStorage!.request(tiles: savedSeeTiles, hash: &storageHash)
        
        
        // Перерисовываем только если загруженные тайлы другие
        if previousStorageHash != storageHash {
            if config.debugRenderLogging {
                print("Tiles storage hash changed")
            }
            // Если тайлы изменились
            // Заменяем пробелы тайлами из предыдущего кадра.
            let placeTilesContext = getPlaceTiles(tilesFromStorage: tilesFromStorage,
                                                  zoom: zoom,
                                                  previousContext: placeTilesContext)
            // Сохраняем текущие тайлы, чтобы заменять отсутствующие тайлы следующего кадра
            self.placeTilesContext = placeTilesContext
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
        let visibleTiles = placeTilesContext.visibleTiles
        
        // Каждый раз проверяет какие тайлы в retain состоянии, а какие нужно удалить
        // Добавляет новые тайлы, которые стали видимы. Пропавшие тайлы удаляет с задержкой, чтобы не сломать анимацию
        trackedTiles = tileRetentionTracker.update(visibleTiles: visibleTiles, now: nowTime)
        let trackedTilesHash = hashTrackedTiles(trackedTiles)
        // Тайлы, которые не заменены для оптимизации
        let detailTrackedTiles = trackedTiles.filter { $0.tile.isCoarseTile == false }
        
        let shouldRebuildLabels = trackedTilesHash != previousTrackedTilesHash
        
        // Квантование. Каждые 0.25 единиц зума будет меняться бакет
        let zoomBucket = Int((cameraControl.zoom * 4.0).rounded(.down))
        var tileUnitsPerPixel = calculateTileUnitsPerPixel(cameraMatrix: cameraMatrix,
                                                           drawSize: drawSize,
                                                           mapSize: mapSize,
                                                           zoom: zoom)
        if tileUnitsPerPixel <= 0.0 {
            tileUnitsPerPixel = previousRoadLabelTileUnitsPerPixel
        }
        let placementScaleDelta = abs(tileUnitsPerPixel - previousRoadLabelTileUnitsPerPixel)
        
        // Должны ли мы пересчитать текст дорожных лейблов
        let shouldUpdateRoadPlacements = shouldRebuildLabels || // если тайлы изменились
            zoomBucket != previousRoadLabelZoomBucket || // если перешли порог зума
            placementScaleDelta > 0.0001 // если есть серьезные изменения в tile units per pixel

        if shouldRebuildLabels {
            previousTrackedTilesHash = trackedTilesHash
            labelCache.rebuild(placeTilesContext: placeTilesContext,
                               trackedTiles: detailTrackedTiles,
                               tileUnitsPerPixel: tileUnitsPerPixel)
            labelCache.updateRoadPathCompute(roadPathScreenCompute)
            previousRoadLabelZoomBucket = zoomBucket
            previousRoadLabelTileUnitsPerPixel = tileUnitsPerPixel
        } else if shouldUpdateRoadPlacements {
            labelCache.rebuildRoadLabelInstances(tileUnitsPerPixel: tileUnitsPerPixel)
            previousRoadLabelZoomBucket = zoomBucket
            previousRoadLabelTileUnitsPerPixel = tileUnitsPerPixel
        }
        
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

        
        // Высчитываем положения текстовых меток
        if viewMode == .spherical {
            tilePointScreenCompute.runGlobe(drawSize: drawSize,
                                            cameraUniform: cameraUniform,
                                            globe: globe,
                                            commandBuffer: commandBuffer)
            roadPathScreenCompute.runGlobe(drawSize: drawSize,
                                           cameraUniform: cameraUniform,
                                           globe: globe,
                                           commandBuffer: commandBuffer)
        } else if viewMode == .flat {
            if let tileOriginDataBuffer {
                tilePointScreenCompute.runFlat(drawSize: drawSize,
                                               cameraUniform: cameraUniform,
                                               tileOriginDataBuffer: tileOriginDataBuffer,
                                               commandBuffer: commandBuffer)
                roadPathScreenCompute.runFlat(drawSize: drawSize,
                                              cameraUniform: cameraUniform,
                                              tileOriginDataBuffer: tileOriginDataBuffer,
                                              commandBuffer: commandBuffer)
            }
        }

        if labelCache.roadLabelGlyphCount > 0 {
            // Вычисляет на GPU экранные позиции и угол поворота каждого глифа дорожного лейбла
            // Берёт screen‑points пути (уже пересчитанные из тайловых координат).
            // Для каждого глифа берёт его anchor (центр лейбла на пути) и смещение внутри текста.
            // Находит точку на пути на нужной дистанции и вычисляет тангент (направление).
            roadLabelPlacementCalculator.run(commandBuffer: commandBuffer,
                                             pathPointsBuffer: roadPathScreenCompute.pointOutputBuffer,
                                             pathRangesBuffer: labelCache.roadPathRangesBuffer,
                                             anchorsBuffer: labelCache.roadLabelAnchorBuffer,
                                             glyphInputsBuffer: labelCache.roadGlyphInputBuffer,
                                             placementsBuffer: labelCache.roadLabelPlacementBuffer,
                                             screenPointsBuffer: labelCache.roadLabelScreenPointsBuffer,
                                             glyphCount: labelCache.roadLabelGlyphCount)
        }
        
        if tilePointScreenCompute.pointsCount > 0 {
            // вычситывает коллизии обычных лейблов
            screenCollisionCalculator.ensureOutputCapacity(count: tilePointScreenCompute.pointsCount)
            screenCollisionCalculator.run(
                commandBuffer: commandBuffer,
                inputsCount: tilePointScreenCompute.pointsCount,
                screenPointsBuffer: tilePointScreenCompute.pointOutputBuffer,
                inputsBuffer: labelCache.collisionInputBuffer
            )

            // шейдер дял fade in / fade out
            labelStateUpdateCalculator.run(
                commandBuffer: commandBuffer,
                inputsCount: tilePointScreenCompute.pointsCount,
                visibilityBuffer: screenCollisionCalculator.outputBuffer,
                labelRuntimeBuffer: labelCache.labelRuntimeBuffer,
                now: Float(nowTime),
                duration: labelFadeDuration
            )
        }

        if labelCache.roadLabelGlyphCount > 0 {
            // высчитывает коллизии между дорогами и лейблами
            roadLabelCollisionCalculator.run(
                commandBuffer: commandBuffer,
                roadCount: labelCache.roadLabelGlyphCount,
                labelCount: tilePointScreenCompute.pointsCount,
                roadPointsBuffer: labelCache.roadLabelScreenPointsBuffer,
                roadCollisionInputsBuffer: labelCache.roadLabelCollisionInputBuffer,
                roadGlyphInputsBuffer: labelCache.roadGlyphInputBuffer,
                labelPointsBuffer: tilePointScreenCompute.pointOutputBuffer,
                labelCollisionInputsBuffer: labelCache.collisionInputBuffer,
                labelVisibilityBuffer: screenCollisionCalculator.outputBuffer
            )
        }

        if labelCache.roadLabelInstancesCount > 0 {
            // проверяет наличие хотя бы одного скрытого глифа в дорожном лейбле
            // если хотя бы один скрыт -> то значит весь дорожный лейбл нужно прятать
            roadLabelVisibilityCalculator.run(
                commandBuffer: commandBuffer,
                glyphVisibilityBuffer: roadLabelCollisionCalculator.outputBuffer,
                glyphRangesBuffer: labelCache.roadLabelGlyphRangesBuffer,
                instanceCount: labelCache.roadLabelInstancesCount
            )

            // анимация fade in / fade out
            labelStateUpdateCalculator.run(
                commandBuffer: commandBuffer,
                inputsCount: labelCache.roadLabelInstancesCount,
                visibilityBuffer: roadLabelVisibilityCalculator.outputBuffer,
                labelRuntimeBuffer: labelCache.roadLabelRuntimeBuffer,
                now: Float(nowTime),
                duration: labelFadeDuration
            )
        }
        
        let transitionMix = Double(transition)
        let spaceColor = config.space.clearColor
        let mapColor = parameters.clearColor
        let clearColor = spaceColor + (mapColor - spaceColor) * transitionMix
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
            // Рисуем космос
            starfield.draw(renderEncoder: renderEncoder,
                           globe: globe,
                           cameraView: cameraView,
                           cameraEye: camera.eye,
                           drawSize: drawSize,
                           nowTime: Float(nowTime))
        }
        
        
        if viewMode == .spherical {
            // Рисуем крышки глобуса
            globeCapRenderer.draw(renderEncoder: renderEncoder,
                                  cameraUniform: cameraUniform,
                                  globe: globe)

            globePipeline.selectPipeline(renderEncoder: renderEncoder)
            
            renderEncoder.setCullMode(.front) // Иначе будет видно обратную строну глобуса.
            renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
            renderEncoder.setVertexBytes(&globe, length: MemoryLayout<Globe>.stride, index: 2)
            renderEncoder.setFragmentTexture(tilesTexture.texture[currentIndex], index: 0)
            renderEncoder.setFragmentBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
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
            for placeTile in placeTilesContext.placeTiles {
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
        
        
        // Рисуем лейблы
        renderEncoder.setRenderPipelineState(textRenderer.labelPipelineState)
        var color = SIMD3<Float>(1.0, 0.0, 0.0)
        var globalTextShift: simd_int1 = 0
        let screenPositions = tilePointScreenCompute.pointOutputBuffer
        let pointInputsBuffer = tilePointScreenCompute.pointInputBuffer
        let collisionOutput = screenCollisionCalculator.outputBuffer
        let labelRuntimeBuffer = labelCache.labelRuntimeBuffer
        var appTime = Float(nowTime)
        renderEncoder.setVertexBytes(&screenMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        renderEncoder.setVertexBuffer(screenPositions, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(pointInputsBuffer, offset: 0, index: 4)
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

        drawRoadPathPointsDebug(renderEncoder: renderEncoder, screenMatrix: screenMatrix)

        // Рисуем дорожные лейблы
        if let roadLabelVerticesBuffer = labelCache.roadLabelVerticesBuffer,
           labelCache.roadLabelVerticesCount > 0 {
            renderEncoder.setRenderPipelineState(textRenderer.roadLabelPipelineState)
            renderEncoder.setVertexBuffer(roadLabelVerticesBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBytes(&screenMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
            renderEncoder.setVertexBuffer(labelCache.roadLabelPlacementBuffer, offset: 0, index: 2)
            renderEncoder.setVertexBuffer(labelCache.roadGlyphInputBuffer, offset: 0, index: 3)
            renderEncoder.setVertexBuffer(labelCache.roadLabelRuntimeBuffer, offset: 0, index: 4)
            renderEncoder.setFragmentTexture(textRenderer.texture, index: 0)
            renderEncoder.setFragmentBytes(&color, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
            renderEncoder.drawPrimitives(type: .triangle,
                                         vertexStart: 0,
                                         vertexCount: labelCache.roadLabelVerticesCount)
        }

        
        
        drawDebugOverlay(renderEncoder: renderEncoder,
                         screenMatrix: screenMatrix,
                         drawSize: drawSize,
                         viewMode: viewMode,
                         cameraUniform: cameraUniform)
        
        renderEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.semaphore.signal()
        }
        didSchedule = true
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

    private func drawRoadPathPointsDebug(renderEncoder: MTLRenderCommandEncoder,
                                         screenMatrix: matrix_float4x4) {
        let pointsCount = roadPathScreenCompute.pointsCount
        guard pointsCount > 0 else {
            return
        }

        screenPointDebugPipeline.setPipelineState(renderEncoder: renderEncoder)
        renderEncoder.setVertexBuffer(roadPathScreenCompute.pointOutputBuffer, offset: 0, index: 0)
        var matrix = screenMatrix
        var color = SIMD4<Float>(1.0, 0.6, 0.0, 1.0)
        renderEncoder.setVertexBytes(&matrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        renderEncoder.setVertexBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 2)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: pointsCount)
    }

    private func calculateTileUnitsPerPixel(cameraMatrix: matrix_float4x4,
                                            drawSize: CGSize,
                                            mapSize: Double,
                                            zoom: Int) -> Float {
        guard drawSize.width > 0.0, drawSize.height > 0.0 else {
            return 0.0
        }

        func project(_ point: SIMD3<Float>) -> SIMD2<Float>? {
            let clip = cameraMatrix * SIMD4<Float>(point, 1.0)
            if clip.w <= 0.0 {
                return nil
            }
            let ndc = SIMD2<Float>(clip.x / clip.w, clip.y / clip.w)
            let viewport = SIMD2<Float>(Float(drawSize.width), Float(drawSize.height))
            return (ndc * 0.5 + SIMD2<Float>(repeating: 0.5)) * viewport
        }

        guard let p0 = project(SIMD3<Float>(0.0, 0.0, 0.0)),
              let p1 = project(SIMD3<Float>(1.0, 0.0, 0.0)) else {
            return 0.0
        }

        let pixelsPerWorldUnit = simd_length(p1 - p0)
        if pixelsPerWorldUnit <= 0.0 {
            return 0.0
        }

        let tilesCount = 1 << zoom
        guard tilesCount > 0 else {
            return 0.0
        }

        let tileWorldSize = Float(mapSize / Double(tilesCount))
        if tileWorldSize <= 0.0 {
            return 0.0
        }

        let tileUnitsPerWorld = Float(4096.0) / tileWorldSize
        let pixelsPerTileUnit = pixelsPerWorldUnit / tileUnitsPerWorld
        if pixelsPerTileUnit <= 0.0 {
            return 0.0
        }

        return 1.0 / pixelsPerTileUnit
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
    
    
    private func getPlaceTiles(tilesFromStorage: [MetalTilesStorage.TileInStorage],
                               zoom: Int,
                               previousContext: PlaceTilesContext) -> PlaceTilesContext {
        var placeTiles: [PlaceTile] = []
        let tileDepthCount = TileDepthCount()
        for i in 0..<tilesFromStorage.count {
            let storageTile = tilesFromStorage[i]
            let metalTile = storageTile.metalTile
            let tile = storageTile.tile
            
            // Ищем один тайл, который полностью покрывает необходимый
            func findFullReplacement() -> Bool? {
                for prev in previousContext.placeTiles {
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
                for prev in previousContext.placeTiles {
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
        
        return PlaceTilesContext(placeTiles: placeTiles)
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
        for i in placeTilesContext.placeTiles.indices {
            let placeTile = placeTilesContext.placeTiles[i]
            let depth = placeTile.depth
            let placed = tilesTexture.draw(placeTile: placeTile, depth: depth, maxDepth: 4)
            if placed == false {
                if config.debugRenderLogging {
                    print("[ERROR] No place for tile in texture!")
                }
                break
            }
        }
    }

    private func hashTrackedTiles(_ tiles: [TileRetentionTracker.TrackedTile]) -> Int {
        var hasher = Hasher()
        hasher.combine(tiles.count)
        for tracked in tiles {
            let tile = tracked.tile
            hasher.combine(tile.x)
            hasher.combine(tile.y)
            hasher.combine(tile.z)
            hasher.combine(tile.loop)
            hasher.combine(tile.isCoarseTile)
            hasher.combine(tracked.isRetained)
        }
        return hasher.finalize()
    }
}
