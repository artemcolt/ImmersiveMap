//
//  FlatVisibleTileResolver.swift
//  ImmersiveMapFramework
//

import simd

enum FlatVisibleTileResolver {
    private static let wrapLoops: [Int8] = [-1, 0, 1]
    static let planeIntersectionTolerance: Float = 1e-5

    static func resolveVisibleTiles(targetZoom: Int,
                                    flatRenderState: FlatRenderState,
                                    camera: Camera) -> Set<VisibleTile> {
        guard targetZoom >= 0,
              let coveragePolygon = makeCoveragePolygon(cameraMatrix: camera.cameraMatrix) else {
            return []
        }

        let tilesCount = 1 << targetZoom
        let mapSize = flatRenderState.renderMapSize
        let tileSize = mapSize / Double(tilesCount)
        guard mapSize.isFinite, tileSize.isFinite, tileSize > 0 else {
            return []
        }

        var visibleTiles: Set<VisibleTile> = []
        visibleTiles.reserveCapacity(coveragePolygon.vertices.count * wrapLoops.count * 4)

        for loop in wrapLoops {
            guard let candidateRange = makeCandidateRange(targetZoom: targetZoom,
                                                          coverageBounds: coveragePolygon.bounds,
                                                          flatRenderState: flatRenderState,
                                                          loop: loop) else {
                continue
            }

            for y in candidateRange.minY...candidateRange.maxY {
                for x in candidateRange.minX...candidateRange.maxX {
                    let tileRect = makeTileRect(x: x,
                                                y: y,
                                                z: targetZoom,
                                                loop: loop,
                                                flatRenderState: flatRenderState)
                    if coveragePolygon.intersects(rect: tileRect) {
                        visibleTiles.insert(VisibleTile(x: x, y: y, z: targetZoom, loop: loop))
                    }
                }
            }
        }

        return visibleTiles
    }

    private static func makeCoveragePolygon(cameraMatrix: matrix_float4x4?) -> CoveragePolygon? {
        guard let cameraMatrix else {
            return nil
        }

        let inverseCameraMatrix = simd_inverse(cameraMatrix)
        let frustumCorners = clipSpaceCorners.compactMap { unprojectClipSpacePoint($0, inverseCameraMatrix: inverseCameraMatrix) }
        guard frustumCorners.count == clipSpaceCorners.count else {
            return nil
        }

        var intersections: [SIMD2<Float>] = []
        intersections.reserveCapacity(frustumEdges.count * 2)

        for edge in frustumEdges {
            appendPlaneIntersections(from: frustumCorners[edge.start],
                                     to: frustumCorners[edge.end],
                                     intersections: &intersections)
        }

        let sortedVertices = sortVerticesClockwise(intersections)
        guard sortedVertices.count >= 3,
              abs(polygonSignedArea(sortedVertices)) > planeIntersectionTolerance else {
            return nil
        }

        return CoveragePolygon(vertices: sortedVertices)
    }

    private static func unprojectClipSpacePoint(_ point: SIMD3<Float>,
                                                inverseCameraMatrix: matrix_float4x4) -> SIMD3<Float>? {
        let homogenous = inverseCameraMatrix * SIMD4<Float>(point.x, point.y, point.z, 1)
        guard homogenous.w.isFinite, abs(homogenous.w) > planeIntersectionTolerance else {
            return nil
        }

        let worldPoint = homogenous / homogenous.w
        guard worldPoint.x.isFinite, worldPoint.y.isFinite, worldPoint.z.isFinite else {
            return nil
        }

        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    private static func appendPlaneIntersections(from start: SIMD3<Float>,
                                                 to end: SIMD3<Float>,
                                                 intersections: inout [SIMD2<Float>]) {
        appendIfPointLiesOnFlatPlane(start, intersections: &intersections)
        appendIfPointLiesOnFlatPlane(end, intersections: &intersections)

        let denominator = start.z - end.z
        guard abs(denominator) > planeIntersectionTolerance else {
            return
        }

        let t = start.z / denominator
        guard t >= -planeIntersectionTolerance, t <= 1 + planeIntersectionTolerance else {
            return
        }

        let clampedT = min(max(t, 0), 1)
        let point = start + (end - start) * clampedT
        guard abs(point.z) <= planeIntersectionTolerance else {
            return
        }

        appendUnique(SIMD2<Float>(point.x, point.y), intersections: &intersections)
    }

    private static func appendIfPointLiesOnFlatPlane(_ point: SIMD3<Float>,
                                                     intersections: inout [SIMD2<Float>]) {
        guard abs(point.z) <= planeIntersectionTolerance else {
            return
        }
        appendUnique(SIMD2<Float>(point.x, point.y), intersections: &intersections)
    }

    private static func appendUnique(_ point: SIMD2<Float>,
                                     intersections: inout [SIMD2<Float>]) {
        for existing in intersections {
            if simd_length_squared(existing - point) <= planeIntersectionTolerance * planeIntersectionTolerance {
                return
            }
        }
        intersections.append(point)
    }

    private static func sortVerticesClockwise(_ vertices: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard vertices.count >= 3 else {
            return []
        }

        let centroid = vertices.reduce(SIMD2<Float>.zero, +) / Float(vertices.count)
        return vertices.sorted { lhs, rhs in
            let lhsAngle = atan2(lhs.y - centroid.y, lhs.x - centroid.x)
            let rhsAngle = atan2(rhs.y - centroid.y, rhs.x - centroid.x)

            if abs(lhsAngle - rhsAngle) > planeIntersectionTolerance {
                return lhsAngle < rhsAngle
            }

            if abs(lhs.x - rhs.x) > planeIntersectionTolerance {
                return lhs.x < rhs.x
            }

            return lhs.y < rhs.y
        }
    }

    private static func polygonSignedArea(_ vertices: [SIMD2<Float>]) -> Float {
        guard vertices.count >= 3 else {
            return 0
        }

        var area: Float = 0
        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            area += vertices[index].x * vertices[nextIndex].y - vertices[nextIndex].x * vertices[index].y
        }
        return area * 0.5
    }

    private static func makeCandidateRange(targetZoom: Int,
                                           coverageBounds: CoverageBounds,
                                           flatRenderState: FlatRenderState,
                                           loop: Int8) -> TileCandidateRange? {
        let tilesCount = 1 << targetZoom
        guard tilesCount > 0 else {
            return nil
        }

        let mapSize = flatRenderState.renderMapSize
        let tileSize = mapSize / Double(tilesCount)
        let halfMapSize = mapSize * 0.5
        let panXOffset = flatRenderState.pan.x * halfMapSize
        let panYOffset = flatRenderState.pan.y * halfMapSize
        let xOffset = -halfMapSize + panXOffset + Double(loop) * mapSize
        let yOffset = -halfMapSize - panYOffset
        let padding = max(tileSize * 1e-6, 1e-6)

        let minColumn = Int(floor((Double(coverageBounds.minX) - xOffset - padding) / tileSize))
        let maxColumn = Int(floor((Double(coverageBounds.maxX) - xOffset + padding) / tileSize))
        let minRowFromBottom = Int(floor((Double(coverageBounds.minY) - yOffset - padding) / tileSize))
        let maxRowFromBottom = Int(floor((Double(coverageBounds.maxY) - yOffset + padding) / tileSize))

        let minY = (tilesCount - 1) - maxRowFromBottom
        let maxY = (tilesCount - 1) - minRowFromBottom

        return TileCandidateRange(minX: clamp(minColumn, lowerBound: 0, upperBound: tilesCount - 1),
                                  maxX: clamp(maxColumn, lowerBound: 0, upperBound: tilesCount - 1),
                                  minY: clamp(minY, lowerBound: 0, upperBound: tilesCount - 1),
                                  maxY: clamp(maxY, lowerBound: 0, upperBound: tilesCount - 1))
            .normalized
    }

    private static func makeTileRect(x: Int,
                                     y: Int,
                                     z: Int,
                                     loop: Int8,
                                     flatRenderState: FlatRenderState) -> AxisAlignedRect {
        let tileOriginAndSize = MapProjection.flatTileOriginAndSize(x: x,
                                                                    y: y,
                                                                    z: z,
                                                                    loop: loop,
                                                                    flatRenderPan: flatRenderState.pan,
                                                                    renderMapSize: flatRenderState.renderMapSize)
        let minX = tileOriginAndSize.x
        let minY = tileOriginAndSize.y
        let maxX = tileOriginAndSize.x + tileOriginAndSize.z
        let maxY = tileOriginAndSize.y + tileOriginAndSize.z
        return AxisAlignedRect(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    private static func clamp(_ value: Int,
                              lowerBound: Int,
                              upperBound: Int) -> Int {
        min(max(value, lowerBound), upperBound)
    }

    private static let clipSpaceCorners: [SIMD3<Float>] = [
        SIMD3<Float>(-1, -1, 0),
        SIMD3<Float>(1, -1, 0),
        SIMD3<Float>(1, 1, 0),
        SIMD3<Float>(-1, 1, 0),
        SIMD3<Float>(-1, -1, 1),
        SIMD3<Float>(1, -1, 1),
        SIMD3<Float>(1, 1, 1),
        SIMD3<Float>(-1, 1, 1)
    ]

    private static let frustumEdges: [(start: Int, end: Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 0),
        (4, 5), (5, 6), (6, 7), (7, 4),
        (0, 4), (1, 5), (2, 6), (3, 7)
    ]
}

private struct CoveragePolygon {
    let vertices: [SIMD2<Float>]
    let bounds: CoverageBounds

    init(vertices: [SIMD2<Float>]) {
        self.vertices = vertices

        var minX = vertices[0].x
        var maxX = vertices[0].x
        var minY = vertices[0].y
        var maxY = vertices[0].y

        for vertex in vertices.dropFirst() {
            minX = min(minX, vertex.x)
            maxX = max(maxX, vertex.x)
            minY = min(minY, vertex.y)
            maxY = max(maxY, vertex.y)
        }

        bounds = CoverageBounds(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    func intersects(rect: AxisAlignedRect) -> Bool {
        if rect.maxX < bounds.minX || rect.minX > bounds.maxX || rect.maxY < bounds.minY || rect.minY > bounds.maxY {
            return false
        }

        if vertices.contains(where: rect.contains(point:)) {
            return true
        }

        if rect.corners.contains(where: contains(point:)) {
            return true
        }

        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            if rect.intersectsSegment(from: vertices[index], to: vertices[nextIndex]) {
                return true
            }
        }

        return false
    }

    private func contains(point: SIMD2<Float>) -> Bool {
        var hasPositiveCross = false
        var hasNegativeCross = false

        for index in vertices.indices {
            let nextIndex = (index + 1) % vertices.count
            let edge = vertices[nextIndex] - vertices[index]
            let relativePoint = point - vertices[index]
            let cross = edge.x * relativePoint.y - edge.y * relativePoint.x

            if cross > FlatVisibleTileResolver.planeIntersectionTolerance {
                hasPositiveCross = true
            } else if cross < -FlatVisibleTileResolver.planeIntersectionTolerance {
                hasNegativeCross = true
            }

            if hasPositiveCross && hasNegativeCross {
                return false
            }
        }

        return true
    }
}

private struct CoverageBounds {
    let minX: Float
    let maxX: Float
    let minY: Float
    let maxY: Float
}

private struct TileCandidateRange {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int

    var normalized: TileCandidateRange? {
        guard minX <= maxX, minY <= maxY else {
            return nil
        }
        return self
    }
}

private struct AxisAlignedRect {
    let minX: Float
    let maxX: Float
    let minY: Float
    let maxY: Float

    var corners: [SIMD2<Float>] {
        [
            SIMD2<Float>(minX, minY),
            SIMD2<Float>(maxX, minY),
            SIMD2<Float>(maxX, maxY),
            SIMD2<Float>(minX, maxY)
        ]
    }

    func contains(point: SIMD2<Float>) -> Bool {
        point.x >= minX - FlatVisibleTileResolver.planeIntersectionTolerance &&
            point.x <= maxX + FlatVisibleTileResolver.planeIntersectionTolerance &&
            point.y >= minY - FlatVisibleTileResolver.planeIntersectionTolerance &&
            point.y <= maxY + FlatVisibleTileResolver.planeIntersectionTolerance
    }

    func intersectsSegment(from start: SIMD2<Float>, to end: SIMD2<Float>) -> Bool {
        if contains(point: start) || contains(point: end) {
            return true
        }

        let rectEdges = [
            (corners[0], corners[1]),
            (corners[1], corners[2]),
            (corners[2], corners[3]),
            (corners[3], corners[0])
        ]

        for edge in rectEdges {
            if segmentsIntersect(start, end, edge.0, edge.1) {
                return true
            }
        }

        return false
    }

    private func segmentsIntersect(_ a1: SIMD2<Float>,
                                   _ a2: SIMD2<Float>,
                                   _ b1: SIMD2<Float>,
                                   _ b2: SIMD2<Float>) -> Bool {
        let orientation1 = orientation(a1, a2, b1)
        let orientation2 = orientation(a1, a2, b2)
        let orientation3 = orientation(b1, b2, a1)
        let orientation4 = orientation(b1, b2, a2)

        if orientation1 * orientation2 < 0 && orientation3 * orientation4 < 0 {
            return true
        }

        if abs(orientation1) <= FlatVisibleTileResolver.planeIntersectionTolerance && onSegment(a1, a2, b1) {
            return true
        }

        if abs(orientation2) <= FlatVisibleTileResolver.planeIntersectionTolerance && onSegment(a1, a2, b2) {
            return true
        }

        if abs(orientation3) <= FlatVisibleTileResolver.planeIntersectionTolerance && onSegment(b1, b2, a1) {
            return true
        }

        if abs(orientation4) <= FlatVisibleTileResolver.planeIntersectionTolerance && onSegment(b1, b2, a2) {
            return true
        }

        return false
    }

    private func orientation(_ a: SIMD2<Float>,
                             _ b: SIMD2<Float>,
                             _ c: SIMD2<Float>) -> Float {
        let ab = b - a
        let ac = c - a
        return ab.x * ac.y - ab.y * ac.x
    }

    private func onSegment(_ start: SIMD2<Float>,
                           _ end: SIMD2<Float>,
                           _ point: SIMD2<Float>) -> Bool {
        point.x >= min(start.x, end.x) - FlatVisibleTileResolver.planeIntersectionTolerance &&
            point.x <= max(start.x, end.x) + FlatVisibleTileResolver.planeIntersectionTolerance &&
            point.y >= min(start.y, end.y) - FlatVisibleTileResolver.planeIntersectionTolerance &&
            point.y <= max(start.y, end.y) + FlatVisibleTileResolver.planeIntersectionTolerance
    }
}
