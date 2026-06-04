// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal
import simd

final class RendererSceneDrawer {
    private struct TileOverviewFadeUniform {
        var overviewAlpha: Float
        var roadAlpha: Float
    }

    private struct ExtrudedLightUniform {
        var direction: SIMD4<Float>
        var color: SIMD4<Float>
        var intensities: SIMD4<Float>
    }

    private struct ExtrudedMaterialUniform {
        var alpha: Float
        var padding: SIMD3<Float> = .zero
    }

    private init() {}

    private static func drawFlatGeometryLayer(renderEncoder: MTLRenderCommandEncoder,
                                              buffers: TileBuffers.GeometryLayer,
                                              tile: Tile,
                                              placeIn: VisibleTile,
                                              flatRenderState: FlatRenderState) {
        guard buffers.indicesCount > 0 else { return }

        let originAndSize = ImmersiveMapProjection.flatTileOriginAndSize(x: tile.x,
                                                                y: tile.y,
                                                                z: tile.z,
                                                                loop: placeIn.loop,
                                                                flatRenderPan: flatRenderState.pan,
                                                                renderMapSize: flatRenderState.renderMapSize)
        let scale = originAndSize.z / 4096.0

        renderEncoder.setVertexBuffer(buffers.verticesBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(buffers.stylesBuffer, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(buffers.overviewStyleMaskBuffer, offset: 0, index: 4)

        var modelMatrix = Matrix.translationMatrix(
            x: originAndSize.x,
            y: originAndSize.y,
            z: 0
        ) * Matrix.scaleMatrix(sx: scale, sy: scale, sz: 1)
        renderEncoder.setVertexBytes(&modelMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 3)

        renderEncoder.drawIndexedPrimitives(type: .triangle,
                                            indexCount: buffers.indicesCount,
                                            indexType: .uint32,
                                            indexBuffer: buffers.indicesBuffer,
                                            indexBufferOffset: 0)
    }

    static func drawSphericalScene(renderEncoder: MTLRenderCommandEncoder,
                                   drawSize: CGSize,
                                   nowTime: TimeInterval,
                                   cameraUniform: CameraUniform,
                                   cameraView: matrix_float4x4,
                                   cameraEye: SIMD3<Float>,
                                   globe: Globe,
                                   starfieldRenderer: StarfieldRenderer,
                                   globeDepthState: MTLDepthStencilState,
                                   globeCapDepthState: MTLDepthStencilState,
                                   depthDisabledState: MTLDepthStencilState,
                                   globeCapRenderer: GlobeCapRenderer,
                                   globePipeline: GlobePipeline,
                                   mapSurfaceGridBuffers: MapSurfaceGridBuffers,
                                   tilesTexture: TilesTexture) {
        starfieldRenderer.draw(renderEncoder: renderEncoder,
                               globe: globe,
                               cameraView: cameraView,
                               cameraEye: cameraEye,
                               drawSize: drawSize,
                               nowTime: Float(nowTime))

        renderEncoder.setDepthStencilState(globeDepthState)

        var cameraUniformValue = cameraUniform
        var globeValue = globe

        globePipeline.selectPipeline(renderEncoder: renderEncoder)
        renderEncoder.setCullMode(.front)
        renderEncoder.setVertexBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBytes(&globeValue, length: MemoryLayout<Globe>.stride, index: 2)
        renderEncoder.setFragmentTexture(tilesTexture.texture, index: 0)
        renderEncoder.setFragmentBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBuffer(mapSurfaceGridBuffers.verticesBuffer, offset: 0, index: 0)

        for mapping in tilesTexture.tileData {
            var mappingValue = mapping
            renderEncoder.setVertexBytes(&mappingValue,
                                         length: MemoryLayout<TilesTexture.TileData>.stride,
                                         index: 3)
            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: mapSurfaceGridBuffers.indicesCount,
                                                indexType: .uint32,
                                                indexBuffer: mapSurfaceGridBuffers.indicesBuffer,
                                                indexBufferOffset: 0)
        }

        renderEncoder.setDepthStencilState(globeCapDepthState)
        globeCapRenderer.draw(renderEncoder: renderEncoder,
                              cameraUniform: cameraUniformValue,
                              globe: globeValue)

        renderEncoder.setDepthStencilState(depthDisabledState)
    }

    static func drawFlatScene(renderEncoder: MTLRenderCommandEncoder,
                              cameraUniform: CameraUniform,
                              cameraZoom: Double,
                              separateRoadRenderingMinimumZoom: Int,
                              placeTilesContext: PlaceTilesContext,
                              flatRenderState: FlatRenderState,
                              tilePipeline: TilePipeline) {
        tilePipeline.selectPipeline(renderEncoder: renderEncoder)
        var cameraUniformValue = cameraUniform
        var overviewFadeUniform = TileOverviewFadeUniform(
            overviewAlpha: LowZoomOverviewFade.alpha(for: cameraZoom, kind: .overviewFeatures),
            roadAlpha: LowZoomOverviewFade.alpha(for: cameraZoom, kind: .roads)
        )
        renderEncoder.setVertexBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setFragmentBytes(&overviewFadeUniform,
                                       length: MemoryLayout<TileOverviewFadeUniform>.stride,
                                       index: 0)

        let usesSeparateRoadRendering = cameraZoom >= Double(separateRoadRenderingMinimumZoom)

        func drawLayer(_ keyPath: KeyPath<TileBuffers, TileBuffers.GeometryLayer>) {
            for placeTile in placeTilesContext.tilePlacements {
                let metalTile = placeTile.metalTile
                drawFlatGeometryLayer(renderEncoder: renderEncoder,
                                      buffers: metalTile.tileBuffers[keyPath: keyPath],
                                      tile: metalTile.tile,
                                      placeIn: placeTile.placeIn,
                                      flatRenderState: flatRenderState)
            }
        }

        drawLayer(\.ground)

        if usesSeparateRoadRendering {
            func drawRoadGroup(_ structureKind: TileMvtParser.RoadStructureKind) {
                for role in [RoadPassRole.shadow, .casing, .fill, .detail] {
                    for placeTile in placeTilesContext.tilePlacements {
                        let metalTile = placeTile.metalTile
                        let structureBucket = metalTile.tileBuffers.roads.bucket(for: structureKind)
                        drawFlatGeometryLayer(renderEncoder: renderEncoder,
                                              buffers: structureBucket.layer(for: role),
                                              tile: metalTile.tile,
                                              placeIn: placeTile.placeIn,
                                              flatRenderState: flatRenderState)
                    }
                }
            }

            drawRoadGroup(.tunnel)
            drawRoadGroup(.ground)
            drawLayer(\.bridgeOverlay)
            drawRoadGroup(.bridge)

            for structureKind in [TileMvtParser.RoadStructureKind.tunnel, .ground, .bridge] {
                for placeTile in placeTilesContext.tilePlacements {
                    let metalTile = placeTile.metalTile
                    let structureBucket = metalTile.tileBuffers.roads.bucket(for: structureKind)
                    drawFlatGeometryLayer(renderEncoder: renderEncoder,
                                          buffers: structureBucket.layer(for: .overlay),
                                          tile: metalTile.tile,
                                          placeIn: placeTile.placeIn,
                                          flatRenderState: flatRenderState)
                }
            }
        } else {
            drawLayer(\.bridgeOverlay)
        }
    }

    static func drawExtrudedScene(renderEncoder: MTLRenderCommandEncoder,
                                  cameraUniform: CameraUniform,
                                  placeTilesContext: PlaceTilesContext,
                                  flatRenderState: FlatRenderState,
                                  buildingExtrusionAlpha: Float,
                                  winnerIDTexture: MTLTexture?,
                                  extrudedTilePipeline: ExtrudedTilePipeline,
                                  extrudedColorPassDepthState: MTLDepthStencilState,
                                  depthDisabledState: MTLDepthStencilState) {
        guard let winnerIDTexture else { return }

        var cameraUniformValue = cameraUniform
        renderEncoder.setCullMode(.back)

        extrudedTilePipeline.selectPipeline(renderEncoder: renderEncoder)
        renderEncoder.setDepthStencilState(extrudedColorPassDepthState)
        renderEncoder.setVertexBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setFragmentTexture(winnerIDTexture, index: 0)
        renderEncoder.setFragmentBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)

        let lightDirection = simd_normalize(SIMD3<Float>(-0.4, -0.6, 1.0))
        var lightUniform = ExtrudedLightUniform(
            direction: SIMD4<Float>(lightDirection, 0.0),
            color: SIMD4<Float>(1.0, 1.0, 1.0, 1.0),
            intensities: SIMD4<Float>(0.35, 0.65, 0.2, 24.0)
        )
        var materialUniform = ExtrudedMaterialUniform(alpha: buildingExtrusionAlpha)
        renderEncoder.setFragmentBytes(&lightUniform, length: MemoryLayout<ExtrudedLightUniform>.stride, index: 2)
        renderEncoder.setFragmentBytes(&materialUniform, length: MemoryLayout<ExtrudedMaterialUniform>.stride, index: 3)
        drawExtrudedGeometry(renderEncoder: renderEncoder,
                             placeTilesContext: placeTilesContext,
                             flatRenderState: flatRenderState)

        renderEncoder.setCullMode(.none)
        renderEncoder.setDepthStencilState(depthDisabledState)
    }

    static func drawExtrudedWinnerPass(commandBuffer: MTLCommandBuffer,
                                       cameraUniform: CameraUniform,
                                       placeTilesContext: PlaceTilesContext,
                                       flatRenderState: FlatRenderState,
                                       winnerIDTexture: MTLTexture,
                                       winnerDepthTexture: MTLTexture,
                                       extrudedTilePipeline: ExtrudedTilePipeline,
                                       extrudedDepthState: MTLDepthStencilState) {
        let renderEncoder = RendererPassEncoderFactory.makeBuildingWinnerEncoder(commandBuffer: commandBuffer,
                                                                                 winnerIDTexture: winnerIDTexture,
                                                                                 winnerDepthTexture: winnerDepthTexture)
        defer { renderEncoder.endEncoding() }

        var cameraUniformValue = cameraUniform
        renderEncoder.setCullMode(.back)
        renderEncoder.setDepthStencilState(extrudedDepthState)
        extrudedTilePipeline.selectWinnerPipeline(renderEncoder: renderEncoder)
        renderEncoder.setVertexBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        drawExtrudedGeometry(renderEncoder: renderEncoder,
                             placeTilesContext: placeTilesContext,
                             flatRenderState: flatRenderState)
    }

    private static func drawExtrudedGeometry(renderEncoder: MTLRenderCommandEncoder,
                                             placeTilesContext: PlaceTilesContext,
                                             flatRenderState: FlatRenderState) {
        for placeTile in placeTilesContext.tilePlacements {
            let metalTile = placeTile.metalTile
            let tile = metalTile.tile
            let buffers = metalTile.tileBuffers
            let placeIn = placeTile.placeIn

            guard buffers.extruded.indicesCount > 0 else { continue }

            let originAndSize = ImmersiveMapProjection.flatTileOriginAndSize(x: tile.x,
                                                                    y: tile.y,
                                                                    z: tile.z,
                                                                    loop: placeIn.loop,
                                                                    flatRenderPan: flatRenderState.pan,
                                                                    renderMapSize: flatRenderState.renderMapSize)
            let scale = originAndSize.z / 4096.0

            renderEncoder.setVertexBuffer(buffers.extruded.verticesBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(buffers.extruded.stylesBuffer, offset: 0, index: 2)

            var modelMatrix = Matrix.translationMatrix(
                x: originAndSize.x,
                y: originAndSize.y,
                z: 0
            ) * Matrix.scaleMatrix(sx: scale, sy: scale, sz: scale)
            renderEncoder.setVertexBytes(&modelMatrix, length: MemoryLayout<matrix_float4x4>.stride, index: 3)

            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: buffers.extruded.indicesCount,
                                                indexType: .uint32,
                                                indexBuffer: buffers.extruded.indicesBuffer,
                                                indexBufferOffset: 0)
        }
    }
}
