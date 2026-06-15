// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import Metal
import simd

struct TileOverlayLineSegment {
    let start: SIMD2<Float>
    let end: SIMD2<Float>
}

private enum TileTextCornerAlignment {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

private struct TileTextCornerAnchor {
    let position: SIMD2<Float>
    let alignment: TileTextCornerAlignment
}

final class DebugOverlayRenderer {
    private var settings: ImmersiveMapSettings.DebugSettings
    private let tileTextVertexBufferStore: FrameSlottedDynamicMetalBuffer<TextVertex>
    private let lineVertexBufferStore: FrameSlottedDynamicMetalBuffer<PolygonsPipeline.Vertex>
    private let tilePointScreenProjector = TilePointScreenProjector()
    private var textVerticesScratch: [TextVertex] = []
    private var lineVerticesScratch: [PolygonsPipeline.Vertex] = []
    private var tileTextEntriesScratch: [TextEntry] = []
    private let tileOutlineThicknessPx: Float = 3.5
    private let tileLabelInsetPx = SIMD2<Float>(8.0, 8.0)
    private let tileLabelTextColor = SIMD3<Float>(1.0, 0.95, 0.2)
    private let tileLabelStrokeColor = SIMD3<Float>(0.0, 0.0, 0.0)
    private let tileLabelStrokeWidthPx: Float = 5.0
    private let tileOutlineColor = SIMD4<Float>(1.0, 0.95, 0.2, 0.95)

    init(metalDevice: MTLDevice,
         settings: ImmersiveMapSettings.DebugSettings) {
        self.settings = settings
        self.tileTextVertexBufferStore = FrameSlottedDynamicMetalBuffer(metalDevice: metalDevice,
                                                                        slotsCount: InFlightFramePool.inFlightFramesCount,
                                                                        options: [.storageModeShared],
                                                                        minimumCapacity: 512)
        self.lineVertexBufferStore = FrameSlottedDynamicMetalBuffer(metalDevice: metalDevice,
                                                                    slotsCount: InFlightFramePool.inFlightFramesCount,
                                                                    options: [.storageModeShared],
                                                                    minimumCapacity: 512)
    }

    convenience init(metalDevice: MTLDevice) {
        self.init(metalDevice: metalDevice, settings: ImmersiveMapSettings.default.debug)
    }

    func apply(settings: ImmersiveMapSettings.DebugSettings) {
        self.settings = settings
    }

    var tileOverlayEnabled: Bool {
        settings.tileOverlayEnabled
    }

    static func makeCoordinateTextLines(zoom: Double,
                                        latitude: Double,
                                        longitude: Double,
                                        locale: Locale = Locale(identifier: "en_US_POSIX")) -> (zoom: String, latLon: String) {
        let numberStyle = FloatingPointFormatStyle<Double>.number.locale(locale)
        let zoomLine = "z: \(zoom.formatted(numberStyle.precision(.fractionLength(2))))"
        let latText = latitude.formatted(numberStyle.precision(.fractionLength(3)))
        let lonText = longitude.formatted(numberStyle.precision(.fractionLength(3)))
        return (zoom: zoomLine, latLon: "lat: \(latText) lon: \(lonText)")
    }

    func drawTileOverlay(renderEncoder: MTLRenderCommandEncoder,
                         polygonPipeline: PolygonsPipeline,
                         textRenderer: TextRenderer,
                         frameContext: FrameContext,
                         placeTiles: [PlaceTile]) {
        guard placeTiles.isEmpty == false else { return }

        tileTextEntriesScratch.removeAll(keepingCapacity: true)
        lineVerticesScratch.removeAll(keepingCapacity: true)
        tileTextEntriesScratch.reserveCapacity(placeTiles.count * 2)
        lineVerticesScratch.reserveCapacity(placeTiles.count * 64)

        let labelScale = max(settings.diagnosticsScale * 0.5, 28.0)
        let labelLineAdvance = makeLineAdvance(textRenderer: textRenderer, scale: labelScale)
        let outlineSegments = Self.makeTileOverlaySegments(segmentCountPerEdge: frameContext.screenSpaceProjectionMode == .flat ? 1 : 8)

        for placeTile in placeTiles {
            appendTileOutlineVertices(into: &lineVerticesScratch,
                                      placeTile: placeTile,
                                      outlineSegments: outlineSegments,
                                      frameContext: frameContext,
                                      color: tileOutlineColor)
            appendTileTextEntries(into: &tileTextEntriesScratch,
                                  placeTile: placeTile,
                                  frameContext: frameContext,
                                  scale: labelScale,
                                  lineAdvance: labelLineAdvance,
                                  textRenderer: textRenderer)
        }

        if lineVerticesScratch.isEmpty == false {
            drawLineVertices(renderEncoder: renderEncoder,
                             polygonPipeline: polygonPipeline,
                             screenMatrix: frameContext.cameraMatrices.screen,
                             frameSlotIndex: frameContext.frameSlotIndex,
                             vertices: lineVerticesScratch)
        }
        if tileTextEntriesScratch.isEmpty == false {
            drawTextEntries(renderEncoder: renderEncoder,
                            textRenderer: textRenderer,
                            screenMatrix: frameContext.cameraMatrices.screen,
                            frameSlotIndex: frameContext.frameSlotIndex,
                            entries: tileTextEntriesScratch,
                            style: TextStyleUniform(textColor: tileLabelTextColor,
                                                    strokeColor: tileLabelStrokeColor,
                                                    strokeWidthPx: tileLabelStrokeWidthPx))
        }
    }

    private func drawTextEntries(renderEncoder: MTLRenderCommandEncoder,
                                 textRenderer: TextRenderer,
                                 screenMatrix: matrix_float4x4,
                                 frameSlotIndex: Int,
                                 entries: [TextEntry],
                                 style: TextStyleUniform? = nil) {
        guard entries.isEmpty == false else { return }
        textRenderer.collectMultiTextVertices(into: &textVerticesScratch, for: entries)
        guard textVerticesScratch.isEmpty == false else { return }

        var textStyle = style ?? TextStyleUniform(textColor: settings.textColor)
        var matrix = screenMatrix
        renderEncoder.setRenderPipelineState(textRenderer.pipelineState)
        setTileTextVertices(renderEncoder: renderEncoder,
                            vertices: textVerticesScratch,
                            frameSlotIndex: frameSlotIndex)
        renderEncoder.setVertexBytes(&matrix, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
        renderEncoder.setFragmentTexture(textRenderer.texture, index: 0)
        renderEncoder.setFragmentBytes(&textStyle, length: MemoryLayout<TextStyleUniform>.stride, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: textVerticesScratch.count)
    }

    private func drawLineVertices(renderEncoder: MTLRenderCommandEncoder,
                                  polygonPipeline: PolygonsPipeline,
                                  screenMatrix: matrix_float4x4,
                                  frameSlotIndex: Int,
                                  vertices: [PolygonsPipeline.Vertex]) {
        guard vertices.isEmpty == false else { return }
        polygonPipeline.setPipelineState(renderEncoder: renderEncoder)
        setLineVertices(renderEncoder: renderEncoder,
                        vertices: vertices,
                        frameSlotIndex: frameSlotIndex)
        var screenUniform = CameraUniform(matrix: screenMatrix,
                                          eye: .zero,
                                          padding: 0.0)
        renderEncoder.setVertexBytes(&screenUniform, length: MemoryLayout<CameraUniform>.stride, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    static func makeOverlayDiagnosticsTextLines(cameraDebugLines: [String],
                                                diagnostics: FrameDiagnostics?) -> [String] {
        guard let diagnostics else {
            return cameraDebugLines
        }
        return cameraDebugLines + makeDiagnosticsTextLines(from: diagnostics)
    }

    private static func makeDiagnosticsTextLines(from diagnostics: FrameDiagnostics) -> [String] {
        let frameLine = "frame: \(diagnostics.frameIndex)  dt: " +
            diagnostics.frameTime.formatted(.number.precision(.fractionLength(2)))
        let tileLine = "tiles vis:\(diagnostics.counterValue(.visibleTiles)) " +
            "ready:\(diagnostics.counterValue(.readyTiles)) " +
            "req:\(diagnostics.counterValue(.requestedTiles)) " +
            "draw:\(diagnostics.counterValue(.renderedTiles))"
        let labelLine = "labels base:\(diagnostics.counterValue(.baseLabelCount)) " +
            "roadG:\(diagnostics.counterValue(.roadLabelGlyphCount)) " +
            "roadI:\(diagnostics.counterValue(.roadLabelInstanceCount))"
        let resourcesLine = "resources b:\(diagnostics.counterValue(.resourceBufferCount)) " +
            "t:\(diagnostics.counterValue(.resourceTextureCount)) " +
            "p:\(diagnostics.counterValue(.resourcePipelineCount))"
        let globeCullingLine = "globeCull ms:\(diagnostics.measurementValue(.globeCullingDurationMs).formatted(.number.precision(.fractionLength(2)))) " +
            "n:\(diagnostics.counterValue(.globeCullingVisitedNodes)) " +
            "f:\(diagnostics.counterValue(.globeCullingFrustumRejects)) " +
            "h:\(diagnostics.counterValue(.globeCullingHorizonRejects)) " +
            "leaf:\(diagnostics.counterValue(.globeCullingAcceptedLeafTiles)) " +
            "acc:\(diagnostics.counterValue(.globeCullingAcceptedWholeSubtrees))"
        let skipLine: String
        if diagnostics.skipReasons.isEmpty {
            skipLine = "skip: none"
        } else {
            let reasons = diagnostics.skipReasons.map(\.rawValue).sorted().joined(separator: ",")
            skipLine = "skip: \(reasons)"
        }
        return [frameLine, tileLine, labelLine, resourcesLine, globeCullingLine, skipLine]
    }

    private func makeLineAdvance(textRenderer: TextRenderer, scale: Float) -> Float {
        let atlasLineHeight = Float(textRenderer.atlasData.metrics.lineHeight)
        return max((atlasLineHeight * scale) + 4.0, scale + 4.0)
    }

    static func formatTileCoordinateString(_ tile: Tile) -> String {
        "\(tile.z)/\(tile.x)/\(tile.y)"
    }

    static func makeDistributedTileCoordinateLines(_ tile: Tile) -> [String] {
        ["z:\(tile.z)", "x:\(tile.x)", "y:\(tile.y)"]
    }

    static func makeTileTextEntries(anchor: SIMD2<Float>,
                                    lines: [String],
                                    scale: Float,
                                    lineAdvance: Float,
                                    padding: SIMD2<Float> = SIMD2<Float>(6.0, 6.0)) -> [TextEntry] {
        guard lines.isEmpty == false else { return [] }

        var entries: [TextEntry] = []
        entries.reserveCapacity(lines.count)
        let startY = anchor.y + (Float(lines.count - 1) * lineAdvance * 0.5)
        for (index, line) in lines.enumerated() {
            entries.append(TextEntry(text: line,
                                     position: SIMD2<Float>(anchor.x + padding.x,
                                                            startY - (Float(index) * lineAdvance) + padding.y),
                                     scale: scale))
        }
        return entries
    }

    static func makeDistributedTileTextEntries(anchorPoints: [SIMD2<Float>],
                                               lines: [String],
                                               scale: Float) -> [TextEntry] {
        guard anchorPoints.isEmpty == false, lines.isEmpty == false else {
            return []
        }

        var entries: [TextEntry] = []
        entries.reserveCapacity(lines.count)
        for (index, line) in lines.enumerated() {
            let anchorPoint = anchorPoints[min(index, anchorPoints.count - 1)]
            entries.append(TextEntry(text: line,
                                     position: anchorPoint,
                                     scale: scale))
        }
        return entries
    }

    private func makeCornerTileTextEntries(anchors: [TileTextCornerAnchor],
                                           lines: [String],
                                           scale: Float,
                                           lineAdvance: Float,
                                           textRenderer: TextRenderer) -> [TextEntry] {
        guard anchors.isEmpty == false, lines.isEmpty == false else {
            return []
        }

        let blockWidth = lines.reduce(Float.zero) { currentMax, line in
            max(currentMax,
                textRenderer.collectLabelVertices(for: line,
                                                  labelIndex: 0,
                                                  scale: scale).size.width)
        }
        let blockHeight = max(0.0, Float(lines.count - 1) * lineAdvance)

        var entries: [TextEntry] = []
        entries.reserveCapacity(anchors.count * lines.count)

        for anchor in anchors {
            let originX: Float
            switch anchor.alignment {
            case .topLeft, .bottomLeft:
                originX = anchor.position.x + tileLabelInsetPx.x
            case .topRight, .bottomRight:
                originX = anchor.position.x - tileLabelInsetPx.x - blockWidth
            }

            let topLineY: Float
            switch anchor.alignment {
            case .topLeft, .topRight:
                topLineY = anchor.position.y - tileLabelInsetPx.y
            case .bottomLeft, .bottomRight:
                topLineY = anchor.position.y + tileLabelInsetPx.y + blockHeight
            }

            for (index, line) in lines.enumerated() {
                entries.append(TextEntry(text: line,
                                         position: SIMD2<Float>(originX,
                                                                topLineY - (Float(index) * lineAdvance)),
                                         scale: scale))
            }
        }

        return entries
    }

    static func makeTileOverlaySegments(segmentCountPerEdge: Int) -> [TileOverlayLineSegment] {
        let clampedSegments = max(1, segmentCountPerEdge)
        let step = 1.0 / Float(clampedSegments)
        var segments: [TileOverlayLineSegment] = []
        segments.reserveCapacity(clampedSegments * 4)

        for index in 0..<clampedSegments {
            let start = Float(index) * step
            let end = Float(index + 1) * step
            segments.append(TileOverlayLineSegment(start: SIMD2<Float>(start, 0.0),
                                                   end: SIMD2<Float>(end, 0.0)))
            segments.append(TileOverlayLineSegment(start: SIMD2<Float>(1.0, start),
                                                   end: SIMD2<Float>(1.0, end)))
            segments.append(TileOverlayLineSegment(start: SIMD2<Float>(1.0 - start, 1.0),
                                                   end: SIMD2<Float>(1.0 - end, 1.0)))
            segments.append(TileOverlayLineSegment(start: SIMD2<Float>(0.0, 1.0 - start),
                                                   end: SIMD2<Float>(0.0, 1.0 - end)))
        }
        return segments
    }

    private func setTileTextVertices(renderEncoder: MTLRenderCommandEncoder,
                                     vertices: [TextVertex],
                                     frameSlotIndex: Int) {
        let length = MemoryLayout<TextVertex>.stride * vertices.count
        if length <= 4096 {
            renderEncoder.setVertexBytes(vertices, length: length, index: 0)
            return
        }

        let buffer = tileTextVertexBufferStore.ensureCapacity(slot: frameSlotIndex,
                                                              count: vertices.count)
        vertices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            memcpy(buffer.contents(), baseAddress, rawBuffer.count)
        }
        renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
    }

    private func setLineVertices(renderEncoder: MTLRenderCommandEncoder,
                                 vertices: [PolygonsPipeline.Vertex],
                                 frameSlotIndex: Int) {
        let length = MemoryLayout<PolygonsPipeline.Vertex>.stride * vertices.count
        if length <= 4096 {
            renderEncoder.setVertexBytes(vertices, length: length, index: 0)
            return
        }

        let buffer = lineVertexBufferStore.ensureCapacity(slot: frameSlotIndex,
                                                          count: vertices.count)
        vertices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            memcpy(buffer.contents(), baseAddress, rawBuffer.count)
        }
        renderEncoder.setVertexBuffer(buffer, offset: 0, index: 0)
    }

    private func appendTileOutlineVertices(into vertices: inout [PolygonsPipeline.Vertex],
                                           placeTile: PlaceTile,
                                           outlineSegments: [TileOverlayLineSegment],
                                           frameContext: FrameContext,
                                           color: SIMD4<Float>) {
        guard outlineSegments.isEmpty == false else { return }

        var pointInputs: [TilePointInput] = []
        pointInputs.reserveCapacity(outlineSegments.count * 2)
        for segment in outlineSegments {
            pointInputs.append(TilePointInput(uv: segment.start,
                                              tile: SIMD3<Int32>(Int32(placeTile.placeIn.x),
                                                                 Int32(placeTile.placeIn.y),
                                                                 Int32(placeTile.placeIn.z)),
                                              tileSlotIndex: 0))
            pointInputs.append(TilePointInput(uv: segment.end,
                                              tile: SIMD3<Int32>(Int32(placeTile.placeIn.x),
                                                                 Int32(placeTile.placeIn.y),
                                                                 Int32(placeTile.placeIn.z)),
                                              tileSlotIndex: 0))
        }

        let snapshot = TilePointToScreenPointSnapshot(pointInputs: pointInputs,
                                                      tileSlotVisibleTileIndices: [0])
        let projectedPoints = tilePointScreenProjector.project(snapshot: snapshot,
                                                               frameContext: frameContext,
                                                               tileOriginData: makeTileOriginData(for: placeTile,
                                                                                                  frameContext: frameContext))
        guard projectedPoints.count == pointInputs.count else { return }

        for segmentIndex in 0..<outlineSegments.count {
            let startPoint = projectedPoints[segmentIndex * 2]
            let endPoint = projectedPoints[(segmentIndex * 2) + 1]
            guard startPoint.visible != 0, endPoint.visible != 0 else {
                continue
            }
            appendThickLineQuad(into: &vertices,
                                start: startPoint.position,
                                end: endPoint.position,
                                thickness: tileOutlineThicknessPx,
                                color: color)
        }
    }

    private func appendTileTextEntries(into entries: inout [TextEntry],
                                       placeTile: PlaceTile,
                                       frameContext: FrameContext,
                                       scale: Float,
                                       lineAdvance: Float,
                                       textRenderer: TextRenderer) {
        let primaryLines = Self.makeDistributedTileCoordinateLines(placeTile.placeIn.tile)
        let primaryAnchors = makeTileLabelCornerAnchors(placeTile: placeTile,
                                                        frameContext: frameContext)
        guard primaryAnchors.isEmpty == false else {
            return
        }
        entries.append(contentsOf: makeCornerTileTextEntries(anchors: primaryAnchors,
                                                             lines: primaryLines,
                                                             scale: scale,
                                                             lineAdvance: lineAdvance,
                                                             textRenderer: textRenderer))

        let sourceTile = placeTile.metalTile.tile
        if placeTile.lodKind != .exact || sourceTile != placeTile.placeIn.tile {
            guard let sourceAnchorPoint = makeTileSourceLabelAnchorPoint(placeTile: placeTile,
                                                                         frameContext: frameContext) else {
                return
            }
            let sourceAnchor = sourceAnchorPoint + SIMD2<Float>(tileLabelInsetPx.x, -tileLabelInsetPx.y)
            entries.append(contentsOf: Self.makeTileTextEntries(anchor: sourceAnchor,
                                                                lines: ["src \(Self.formatTileCoordinateString(sourceTile))"],
                                                                scale: max(scale * 0.72, 20.0),
                                                                lineAdvance: lineAdvance,
                                                                padding: .zero))
        }
    }

    private func makeTileOriginData(for placeTile: PlaceTile,
                                    frameContext: FrameContext) -> [FlatTileOriginData] {
        guard frameContext.screenSpaceProjectionMode == .flat else {
            return []
        }

        let originAndSize = ImmersiveMapProjection.flatTileOriginAndSize(x: placeTile.placeIn.x,
                                                                y: placeTile.placeIn.y,
                                                                z: placeTile.placeIn.z,
                                                                loop: placeTile.placeIn.loop,
                                                                flatRenderPan: frameContext.flatRenderState.pan,
                                                                renderMapSize: frameContext.flatRenderState.renderMapSize)
        return [FlatTileOriginData(panRelativeOrigin: SIMD2<Float>(originAndSize.x, originAndSize.y),
                                   size: originAndSize.z)]
    }

    private func makeTileLabelCornerAnchors(placeTile: PlaceTile,
                                            frameContext: FrameContext) -> [TileTextCornerAnchor] {
        let candidates: [(uv: SIMD2<Float>, alignment: TileTextCornerAlignment)] = [
            (SIMD2<Float>(0.14, 0.14), .topLeft),
            (SIMD2<Float>(0.86, 0.14), .topRight),
            (SIMD2<Float>(0.14, 0.86), .bottomLeft),
            (SIMD2<Float>(0.86, 0.86), .bottomRight)
        ]
        let pointInputs = candidates.map {
            TilePointInput(uv: $0.uv,
                           tile: SIMD3<Int32>(Int32(placeTile.placeIn.x),
                                              Int32(placeTile.placeIn.y),
                                              Int32(placeTile.placeIn.z)),
                           tileSlotIndex: 0)
        }
        let snapshot = TilePointToScreenPointSnapshot(pointInputs: pointInputs,
                                                      tileSlotVisibleTileIndices: [0])
        let points = tilePointScreenProjector.project(snapshot: snapshot,
                                                      frameContext: frameContext,
                                                      tileOriginData: makeTileOriginData(for: placeTile,
                                                                                         frameContext: frameContext))
        var anchors: [TileTextCornerAnchor] = []
        anchors.reserveCapacity(candidates.count)

        for (index, candidate) in candidates.enumerated() where index < points.count {
            let point = points[index]
            guard point.visible != 0 else { continue }
            anchors.append(TileTextCornerAnchor(position: point.position,
                                                alignment: candidate.alignment))
        }
        return anchors
    }

    private func makeTileSourceLabelAnchorPoint(placeTile: PlaceTile,
                                                frameContext: FrameContext) -> SIMD2<Float>? {
        let candidateUVs: [SIMD2<Float>] = [
            SIMD2<Float>(0.55, 0.82),
            SIMD2<Float>(0.55, 0.68),
            SIMD2<Float>(0.5, 0.5)
        ]
        let pointInputs = candidateUVs.map {
            TilePointInput(uv: $0,
                           tile: SIMD3<Int32>(Int32(placeTile.placeIn.x),
                                              Int32(placeTile.placeIn.y),
                                              Int32(placeTile.placeIn.z)),
                           tileSlotIndex: 0)
        }
        let snapshot = TilePointToScreenPointSnapshot(pointInputs: pointInputs,
                                                      tileSlotVisibleTileIndices: [0])
        let points = tilePointScreenProjector.project(snapshot: snapshot,
                                                      frameContext: frameContext,
                                                      tileOriginData: makeTileOriginData(for: placeTile,
                                                                                         frameContext: frameContext))
        return points.first(where: { $0.visible != 0 })?.position
    }

    private func appendThickLineQuad(into vertices: inout [PolygonsPipeline.Vertex],
                                     start: SIMD2<Float>,
                                     end: SIMD2<Float>,
                                     thickness: Float,
                                     color: SIMD4<Float>) {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0.001 else { return }

        let direction = delta / length
        let normal = SIMD2<Float>(-direction.y, direction.x) * (thickness * 0.5)

        let a = start + normal
        let b = end + normal
        let c = end - normal
        let d = start - normal

        vertices.append(PolygonsPipeline.Vertex(position: SIMD4<Float>(a.x, a.y, 0.0, 1.0), color: color))
        vertices.append(PolygonsPipeline.Vertex(position: SIMD4<Float>(b.x, b.y, 0.0, 1.0), color: color))
        vertices.append(PolygonsPipeline.Vertex(position: SIMD4<Float>(c.x, c.y, 0.0, 1.0), color: color))

        vertices.append(PolygonsPipeline.Vertex(position: SIMD4<Float>(a.x, a.y, 0.0, 1.0), color: color))
        vertices.append(PolygonsPipeline.Vertex(position: SIMD4<Float>(c.x, c.y, 0.0, 1.0), color: color))
        vertices.append(PolygonsPipeline.Vertex(position: SIMD4<Float>(d.x, d.y, 0.0, 1.0), color: color))
    }
}
