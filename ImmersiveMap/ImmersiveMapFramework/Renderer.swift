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
    private let frame: Frame
    private let metalTilesStorage: MetalTilesStorage
    private let tilesTexture: TilesTexture
    
    private let sphereVerticesBuffer: MTLBuffer
    private let sphereIndicesBuffer: MTLBuffer
    private let sphereIndicesCount: Int
    
//    private let depthStencilState: MTLDepthStencilState
//    private let noDepthStencilState: MTLDepthStencilState
//    private let equalDepthStencilState: MTLDepthStencilState
    
    private let semaphore = DispatchSemaphore(value: 3)
    private var currentIndex = 0
    
    private let tile: Tile = Tile(x: 0, y: 0, z: 0)
    
    let vertices: [PolygonsPipeline.Vertex] = [
        // axes
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(1, 0, 0, 1)),
        PolygonsPipeline.Vertex(position: SIMD4<Float>(1.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(1, 0, 0, 1)),
        
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(0, 1, 0, 1)),
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 1.0, 0.0, 1.0),   color: SIMD4<Float>(0, 1, 0, 1)),
        
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),   color: SIMD4<Float>(0, 0, 1, 1)),
        PolygonsPipeline.Vertex(position: SIMD4<Float>(0.0, 0.0, 1.0, 1.0),   color: SIMD4<Float>(0, 0, 1, 1)),
    ]
    
    init(layer: CAMetalLayer) {
        self.metalLayer = layer
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
            
//        let depthStencilDescriptor = MTLDepthStencilDescriptor()
//        depthStencilDescriptor.depthCompareFunction = .less
//        depthStencilDescriptor.isDepthWriteEnabled = true
//        depthStencilState = metalDevice.makeDepthStencilState(descriptor: depthStencilDescriptor)!
//        
//        depthStencilDescriptor.depthCompareFunction = .equal
//        depthStencilDescriptor.isDepthWriteEnabled = false
//        equalDepthStencilState = metalDevice.makeDepthStencilState(descriptor: depthStencilDescriptor)!
//        
//        depthStencilDescriptor.depthCompareFunction = .always
//        depthStencilDescriptor.isDepthWriteEnabled = false
//        noDepthStencilState = metalDevice.makeDepthStencilState(descriptor: depthStencilDescriptor)!
        
        let bundle = Bundle(for: Renderer.self)
        let library = try! metalDevice.makeDefaultLibrary(bundle: bundle)
        
        polygonPipeline = PolygonsPipeline(metalDevice: metalDevice, layer: layer, library: library)
        tilePipeline = TilePipeline(metalDevice: metalDevice, layer: layer, library: library)
        globePipeline = GlobePipeline(metalDevice: metalDevice, layer: layer, library: library)
        
        tilesTexture = TilesTexture(metalDevice: metalDevice, tilePipeline: tilePipeline)
        camera = Camera()
        cameraControl = CameraControl()
        frame = Frame(metalDevice: metalDevice)
        metalTilesStorage = MetalTilesStorage(mapStyle: DefaultMapStyle(), metalDevice: metalDevice)
        
        
        let sphereGeometry = SphereGeometry(stacks: 128, slices: 128)
        let vertices = sphereGeometry.vertices
        let indices = sphereGeometry.indices
        sphereVerticesBuffer = metalDevice.makeBuffer(bytes: vertices, length: MemoryLayout<SphereGeometry.Vertex>.stride * vertices.count)!
        sphereIndicesBuffer = metalDevice.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count)!
        sphereIndicesCount = indices.count
        
        
        metalTilesStorage.addHandler(handler: tileReady)
    }
    
    private func tileReady(tile: Tile) {
        render(to: metalLayer)
    }
    
    private var previousTiles: [Tile] = []
    
    func render(to layer: CAMetalLayer) {
        semaphore.wait()
        
        let nextIndex = (currentIndex + 1) % 3
        currentIndex = nextIndex
        
        frame.prepare(layer: layer, camera: camera, index: currentIndex)
        
        if cameraControl.update {
            let yaw = cameraControl.yaw
            let pitch = cameraControl.pitch
            
            let zRemains = cameraControl.zoom.truncatingRemainder(dividingBy: 1.0)
            let camUp = SIMD3<Float>(0, 1, 0)
            let camDirection = SIMD3<Float>(0, 0, (1.0 - zRemains * 0.5))
            let camRight = SIMD3<Float>(1, 0, 0)
            
            let pitchQuat = simd_quatf(angle: pitch, axis: camRight)
            let yawQuat = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 0, 1))
            
            camera.eye = simd_act(yawQuat * pitchQuat, camDirection)
            camera.up = simd_act(yawQuat * pitchQuat, camUp)
//            camera.center = SIMD3<Float>(Float(cameraControl.pan.x), 0, 0)
            
            camera.recalculateMatrix()
            cameraControl.update = false
        }
        let worldScale = pow(2.0, floor(cameraControl.zoom))
        
        let frameData = frame.data[currentIndex]
        guard let frameTexture = frameData.msaaTexture,
              let depthStencilTexture = frameData.depthStencilTexture,
              let cameraMatrix = camera.cameraMatrix,
              let drawable = layer.nextDrawable() else {
            semaphore.signal()
            return
        }
        
        let clearColor = parameters.clearColor
        let commandBuffer = commandQueue.makeCommandBuffer()!
        
        var globe = Globe(xRotation: Float(cameraControl.pan.y) * Float.pi / 2.0,
                          yRotation: Float(cameraControl.pan.x) * Float.pi,
                          radius: 0.15 * worldScale)
        
        //let vis = getVisibleTiles(globe: globe, targetZoom: Int(cameraControl.zoom))
        let vis = [Tile(x: 0, y: 0, z: 0)]
        
        let tilesAmount = Int(pow(2.0, Double(Int(cameraControl.zoom))) * pow(2.0, Double(Int(cameraControl.zoom))))
        print("-------------------------------------------------")
        print("\(vis.count)/\(tilesAmount)")
        
        tilesTexture.activateEncoder(commandBuffer: commandBuffer, index: currentIndex)
        
        var currentTiles: [Tile] = []
        for i in 0..<vis.count {
            let t = vis[i]
            let tile = Tile(x: t.x, y: t.y, z: t.z)
            
            var metalTile = metalTilesStorage.getMetalTile(tile: tile)
            if metalTile == nil {
                metalTilesStorage.requestMetalTile(tile: tile)
                
                for prevTile in previousTiles {
                    if prevTile.covers(tile) || tile.covers(prevTile) {
                        metalTile = metalTilesStorage.getMetalTile(tile: prevTile)!
                    }
                }
            }
            
            guard let metalTile = metalTile else { continue }
            
            currentTiles.append(metalTile.tile)
            let placed = tilesTexture.draw(metalTile: metalTile)
            if placed == false {
                print("no place for tile")
                break
            }
        }
        tilesTexture.endEncoding()
        previousTiles = currentTiles
        
        
        // Camera uniform
        var cameraUniform = CameraUniform(matrix: cameraMatrix)
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = frameTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: clearColor.x,
                                                                            green: clearColor.y,
                                                                            blue: clearColor.z,
                                                                            alpha: clearColor.w)
        renderPassDescriptor.colorAttachments[0].storeAction = .multisampleResolve
        renderPassDescriptor.colorAttachments[0].resolveTexture = drawable.texture
        
        renderPassDescriptor.depthAttachment.texture = depthStencilTexture
        renderPassDescriptor.depthAttachment.loadAction = .clear
        renderPassDescriptor.depthAttachment.clearDepth = 1.0
        renderPassDescriptor.depthAttachment.storeAction = .dontCare
        
        renderPassDescriptor.stencilAttachment.texture = depthStencilTexture
        renderPassDescriptor.stencilAttachment.loadAction = .load
        renderPassDescriptor.stencilAttachment.clearStencil = 0
        renderPassDescriptor.stencilAttachment.storeAction = .dontCare
        
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
        
        
        
        // axes
        polygonPipeline.setPipelineState(renderEncoder: renderEncoder)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBytes(&cameraUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 6)
        
        for point in camera.testPoints {
            let verticesTest = [PolygonsPipeline.Vertex(position: point, color: SIMD4<Float>(1, 0, 0, 1))]
            renderEncoder.setVertexBytes(verticesTest, length: MemoryLayout<PolygonsPipeline.Vertex>.stride * verticesTest.count, index: 0)
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: verticesTest.count)
        }
        
        renderEncoder.endEncoding()
        
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.semaphore.signal()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func getVisibleTiles(globe: Renderer.Globe, targetZoom: Int) -> [Tile] {
        let pan = cameraControl.pan
        let tileX = Int(-(pan.x - 1.0) / 2.0 * Double(1 << targetZoom))
        
        let maxLat = 85.05112878
        let lat_deg = max(-maxLat, min(maxLat, pan.y * maxLat))
        let lat_rad = lat_deg * Double.pi / 180.0
        let merc_factor = log(tan(lat_rad) + (1.0 / cos(lat_rad)))
        let n = Double(1 << targetZoom)
        let fractional_y = (1.0 - merc_factor / Double.pi) / 2.0 * n
        let tileY = Int(floor(fractional_y))
        
        guard let pv = camera.cameraMatrix else { return [] }
        let frustum = Frustum(pv: pv)
        
        camera.testPoints = []
        var result: [Tile] = []
        camera.collectVisibleTiles(x: 0, y: 0, z: 0, targetZ: targetZoom, globe: globe, frustrum: frustum, result: &result,
                                   centerTile: Tile(x: tileX, y: tileY, z: targetZoom)
        )
        
        print("tileX \(tileX) tileY \(tileY) pan.y \(pan.y)")
        
        result.sort { (t1, t2) -> Bool in
            let dx1 = abs(t1.x - tileX)
            let dy1 = abs(t1.y - tileY)
            let maxD1 = max(dx1, dy1)
            
            let dx2 = abs(t2.x - tileX)
            let dy2 = abs(t2.y - tileY)
            let maxD2 = max(dx2, dy2)
            
            if t1.z == t2.z {
                return maxD1 > maxD2
            } else {
                return t1.z < t2.z
            }
        }
        //print(result)
        
        return result
    }
}
