//
//  RendererLabelDrawer.swift
//  ImmersiveMapFramework
//  Created by Artem on 3/10/26.
//

import Metal
import simd

final class RendererLabelDrawer {
    private init() {}

    static func drawBaseLabels(renderEncoder: MTLRenderCommandEncoder,
                               screenMatrix: matrix_float4x4,
                               textRenderer: TextRenderer,
                               poiSpriteAtlas: PoiSpriteAtlas,
                               screenPositionsBuffer: MTLBuffer,
                               collisionFlagsBuffer: MTLBuffer,
                               labelRuntimeMetaBuffer: MTLBuffer,
                               baseLabelsDrawBatches: [BaseLabelDrawBatch]) {
        var screenMatrixValue = screenMatrix

        renderEncoder.setVertexBytes(&screenMatrixValue, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        renderEncoder.setVertexBuffer(screenPositionsBuffer, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(collisionFlagsBuffer, offset: 0, index: 5)
        renderEncoder.setVertexBuffer(labelRuntimeMetaBuffer, offset: 0, index: 6)

        for drawBatch in baseLabelsDrawBatches {
            for poiIconRun in drawBatch.poiIconRuns {
                guard let poiIconVerticesBuffer = poiIconRun.localVerticesBuffer,
                      poiIconRun.localVertexCount > 0 else {
                    continue
                }

                renderEncoder.setRenderPipelineState(textRenderer.poiIconPipelineState)
                renderEncoder.setFragmentTexture(poiSpriteAtlas.texture, index: 0)
                var iconStyle = PoiIconStyleUniform(
                    backgroundColor: SIMD4<Float>(poiIconRun.style.fillColor.x,
                                                  poiIconRun.style.fillColor.y,
                                                  poiIconRun.style.fillColor.z,
                                                  1.0),
                    iconColor: SIMD4<Float>(1.0, 1.0, 1.0, 1.0)
                )
                renderEncoder.setFragmentBytes(&iconStyle,
                                               length: MemoryLayout<PoiIconStyleUniform>.stride,
                                               index: 0)
                renderEncoder.setVertexBuffer(poiIconVerticesBuffer, offset: 0, index: 0)
                var globalIconShift = simd_int1(drawBatch.globalLabelStart)
                renderEncoder.setVertexBytes(&globalIconShift, length: MemoryLayout<simd_int1>.stride, index: 3)
                renderEncoder.drawPrimitives(type: .triangle,
                                             vertexStart: 0,
                                             vertexCount: poiIconRun.localVertexCount)
            }
        }

        renderEncoder.setRenderPipelineState(textRenderer.labelPipelineState)
        for drawBatch in baseLabelsDrawBatches {
            for run in drawBatch.labelsByStyleRuns {
                guard let localGlyphVerticesBuffer = run.localGlyphVerticesBuffer,
                      run.localGlyphVertexCount > 0 else {
                    continue
                }

                let style = run.style
                let texture = style.weight == .bold ? textRenderer.texture : textRenderer.thinTexture
                var textStyle = TextStyleUniform(textColor: style.fillColor,
                                                 strokeColor: style.strokeColor,
                                                 strokeWidthPx: style.strokeWidthPx)

                renderEncoder.setFragmentTexture(texture, index: 0)
                renderEncoder.setFragmentBytes(&textStyle,
                                               length: MemoryLayout<TextStyleUniform>.stride,
                                               index: 0)
                renderEncoder.setVertexBuffer(localGlyphVerticesBuffer, offset: 0, index: 0)
                var globalTextShift = simd_int1(drawBatch.globalLabelStart)
                renderEncoder.setVertexBytes(&globalTextShift, length: MemoryLayout<simd_int1>.stride, index: 3)
                renderEncoder.drawPrimitives(type: .triangle,
                                             vertexStart: 0,
                                             vertexCount: run.localGlyphVertexCount)
            }
        }
    }

    static func drawRoadLabels(renderEncoder: MTLRenderCommandEncoder,
                               screenMatrix: matrix_float4x4,
                               textRenderer: TextRenderer,
                               roadDrawLabels: [DrawRoadLabels]) {
        guard roadDrawLabels.isEmpty == false else {
            return
        }

        renderEncoder.setRenderPipelineState(textRenderer.roadLabelPipelineState)
        var screenMatrixValue = screenMatrix
        renderEncoder.setVertexBytes(&screenMatrixValue, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        for drawLabel in roadDrawLabels {
            guard let placementBuffer = drawLabel.placementBuffer,
                  let glyphInputBuffer = drawLabel.glyphInputBuffer,
                  let runtimeMetaBuffer = drawLabel.runtimeMetaBuffer,
                  let localGlyphVerticesBuffer = drawLabel.localGlyphVerticesBuffer,
                  drawLabel.localGlyphVertexCount > 0 else {
                continue
            }

            renderEncoder.setVertexBuffer(placementBuffer, offset: 0, index: 2)
            renderEncoder.setVertexBuffer(glyphInputBuffer, offset: 0, index: 3)
            renderEncoder.setVertexBuffer(runtimeMetaBuffer, offset: 0, index: 4)
            renderEncoder.setVertexBuffer(localGlyphVerticesBuffer, offset: 0, index: 0)

            let style = drawLabel.labelStyle
                ?? LabelTextStyle(key: 0,
                                  fillColor: SIMD3<Float>(0.54, 0.54, 0.52),
                                  strokeColor: SIMD3<Float>(0.54, 0.54, 0.52),
                                  strokeWidthPx: 0.0,
                                  sizePx: 36.0,
                                  weight: .thin)
            let texture = style.weight == .bold ? textRenderer.texture : textRenderer.thinTexture
            renderEncoder.setFragmentTexture(texture, index: 0)

            var glyphShift: simd_int1 = 0
            renderEncoder.setVertexBytes(&glyphShift, length: MemoryLayout<simd_int1>.stride, index: 5)
            let outlineRadius = max(0.0, min(style.strokeWidthPx, 2.0))
            if outlineRadius > 0.0 {
                let outlineOffsets: [SIMD2<Float>] = [
                    SIMD2<Float>(outlineRadius, 0.0),
                    SIMD2<Float>(-outlineRadius, 0.0),
                    SIMD2<Float>(0.0, outlineRadius),
                    SIMD2<Float>(0.0, -outlineRadius),
                    SIMD2<Float>(outlineRadius * 0.7071, outlineRadius * 0.7071),
                    SIMD2<Float>(outlineRadius * 0.7071, -outlineRadius * 0.7071),
                    SIMD2<Float>(-outlineRadius * 0.7071, outlineRadius * 0.7071),
                    SIMD2<Float>(-outlineRadius * 0.7071, -outlineRadius * 0.7071)
                ]
                var outlineStyle = TextStyleUniform(textColor: style.strokeColor,
                                                    strokeColor: style.strokeColor,
                                                    strokeWidthPx: 0.0)
                renderEncoder.setFragmentBytes(&outlineStyle,
                                               length: MemoryLayout<TextStyleUniform>.stride,
                                               index: 0)
                for offset in outlineOffsets {
                    var outlineOffset = offset
                    renderEncoder.setVertexBytes(&outlineOffset,
                                                 length: MemoryLayout<SIMD2<Float>>.stride,
                                                 index: 6)
                    renderEncoder.drawPrimitives(type: .triangle,
                                                 vertexStart: 0,
                                                 vertexCount: drawLabel.localGlyphVertexCount)
                }
            }

            var fillStyle = TextStyleUniform(textColor: style.fillColor,
                                             strokeColor: style.fillColor,
                                             strokeWidthPx: 0.0)
            renderEncoder.setFragmentBytes(&fillStyle,
                                           length: MemoryLayout<TextStyleUniform>.stride,
                                           index: 0)
            var fillOffset = SIMD2<Float>(repeating: 0.0)
            renderEncoder.setVertexBytes(&fillOffset,
                                         length: MemoryLayout<SIMD2<Float>>.stride,
                                         index: 6)
            renderEncoder.drawPrimitives(type: .triangle,
                                         vertexStart: 0,
                                         vertexCount: drawLabel.localGlyphVertexCount)
        }
    }
}
