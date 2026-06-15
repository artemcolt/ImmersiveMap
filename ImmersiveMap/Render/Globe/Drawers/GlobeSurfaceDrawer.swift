// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

enum GlobeSurfaceDrawer {
    static func draw(renderEncoder: MTLRenderCommandEncoder,
                     cameraUniform: CameraUniform,
                     globe: GlobeUniform,
                     earthScene: EarthSceneUniform,
                     nightLightsTexture: MTLTexture,
                     globePipeline: GlobePipeline,
                     mapSurfaceGridBuffers: MapSurfaceGridBuffers,
                     tilesTexture: GlobeTilesTexture) {
        var cameraUniformValue = cameraUniform
        var earthSceneValue = earthScene
        var globeValue = globe

        globePipeline.selectPipeline(renderEncoder: renderEncoder)
        renderEncoder.setCullMode(.front)
        renderEncoder.setVertexBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setVertexBytes(&globeValue, length: MemoryLayout<GlobeUniform>.stride, index: 2)
        renderEncoder.setFragmentBytes(&cameraUniformValue, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.setFragmentBytes(&earthSceneValue, length: MemoryLayout<EarthSceneUniform>.stride, index: 2)
        renderEncoder.setFragmentTexture(nightLightsTexture, index: 1)
        renderEncoder.setVertexBuffer(mapSurfaceGridBuffers.verticesBuffer, offset: 0, index: 0)

        var pageMappings: [(pageIndex: Int, mapping: GlobeTilesTexture.TileData)] = []
        for (pageIndex, page) in tilesTexture.pages.enumerated() {
            for mapping in page.tileData {
                pageMappings.append((pageIndex: pageIndex, mapping: mapping))
            }
        }
        pageMappings.sort { $0.pageIndex < $1.pageIndex }

        var activePageIndex: Int?
        for pageMapping in pageMappings {
            if activePageIndex != pageMapping.pageIndex {
                renderEncoder.setFragmentTexture(tilesTexture.pages[pageMapping.pageIndex].texture, index: 0)
                activePageIndex = pageMapping.pageIndex
            }
            let mapping = pageMapping.mapping
            var mappingValue = mapping
            renderEncoder.setVertexBytes(&mappingValue,
                                         length: MemoryLayout<GlobeTilesTexture.TileData>.stride,
                                         index: 3)
            renderEncoder.drawIndexedPrimitives(type: .triangle,
                                                indexCount: mapSurfaceGridBuffers.indicesCount,
                                                indexType: .uint32,
                                                indexBuffer: mapSurfaceGridBuffers.indicesBuffer,
                                                indexBufferOffset: 0)
        }
    }
}
