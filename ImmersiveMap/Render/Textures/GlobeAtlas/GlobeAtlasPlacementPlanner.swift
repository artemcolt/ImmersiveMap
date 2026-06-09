// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation
import simd

struct GlobeAtlasPlacementPlanner {
    let pageSizePx: Int
    let maxPageCount: Int
    let qualityScale: Float

    init(pageSizePx: Int = 4096,
         maxPageCount: Int = 3,
         qualityScale: Float = 1.0) {
        self.pageSizePx = pageSizePx
        self.maxPageCount = max(1, maxPageCount)
        self.qualityScale = max(0.25, qualityScale)
    }

    static func makeCandidateForTesting(placementIndex: Int,
                                        placeTile: PlaceTile,
                                        screenBoundsPx: CGRect,
                                        pageSizePx: Int,
                                        qualityScale: Float = 1.0) -> GlobeAtlasCandidate {
        let demand = Float(max(screenBoundsPx.width, screenBoundsPx.height))
        return GlobeAtlasCandidate(placementIndex: placementIndex,
                                   placeTile: placeTile,
                                   layer: .base,
                                   screenDemandPx: demand,
                                   distanceToCamera: 0,
                                   desiredDepth: GlobeAtlasSlotDepth.desired(forScreenDemandPx: demand,
                                                                             pageSizePx: pageSizePx,
                                                                             qualityScale: qualityScale))
    }

    static func screenFootprintForTesting(projectedSamples: [(position: SIMD2<Float>,
                                                              depth: Float,
                                                              passesHorizon: Bool)],
                                          viewport: SIMD2<Float>) -> CGRect? {
        var minimumX = Float.greatestFiniteMagnitude
        var minimumY = Float.greatestFiniteMagnitude
        var maximumX = -Float.greatestFiniteMagnitude
        var maximumY = -Float.greatestFiniteMagnitude
        var hasVisibleSample = false

        for sample in projectedSamples where sample.passesHorizon {
            let clampedPosition = SIMD2<Float>(simd_clamp(sample.position.x, 0, viewport.x),
                                               simd_clamp(sample.position.y, 0, viewport.y))
            minimumX = min(minimumX, clampedPosition.x)
            minimumY = min(minimumY, clampedPosition.y)
            maximumX = max(maximumX, clampedPosition.x)
            maximumY = max(maximumY, clampedPosition.y)
            hasVisibleSample = true
        }

        guard hasVisibleSample else { return nil }
        return CGRect(x: CGFloat(minimumX),
                      y: CGFloat(minimumY),
                      width: CGFloat(max(1, maximumX - minimumX)),
                      height: CGFloat(max(1, maximumY - minimumY)))
    }

    func makeCandidates(placeTiles: [PlaceTile],
                        frameContext: FrameContext) -> [GlobeAtlasCandidate] {
        let texturePlaceTiles = placeTiles.map {
            GlobeTexturePlaceTile(placeTile: $0, layer: .base)
        }
        return makeCandidates(placeTiles: texturePlaceTiles,
                              frameContext: frameContext)
    }

    func makeCandidates(placeTiles: [GlobeTexturePlaceTile],
                        frameContext: FrameContext) -> [GlobeAtlasCandidate] {
        placeTiles.enumerated().compactMap { index, placeTile in
            guard let footprint = estimateScreenFootprint(placeTile: placeTile.placeTile,
                                                          frameContext: frameContext) else {
                return nil
            }

            let demand = Float(max(footprint.bounds.width, footprint.bounds.height))
            return GlobeAtlasCandidate(placementIndex: index,
                                       placeTile: placeTile.placeTile,
                                       layer: placeTile.layer,
                                       screenDemandPx: demand,
                                       distanceToCamera: footprint.minimumDepth,
                                       desiredDepth: GlobeAtlasSlotDepth.desired(forScreenDemandPx: demand,
                                                                                 pageSizePx: pageSizePx,
                                                                                 qualityScale: qualityScale))
        }
    }

    func plan(candidates: [GlobeAtlasCandidate]) -> GlobeAtlasPlan {
        guard !candidates.isEmpty else { return .empty }

        var pages: [Page] = []
        var allocations: [GlobeAtlasAllocation] = []
        var downgradedAllocationCount = 0
        var skippedAllocationCount = 0
        let baseCandidates = candidates.filter { $0.layer == .base }
        let detailCandidates = candidates.filter { $0.layer == .detail }
        let baseCoverageDepth = coverageDepth(candidateCount: baseCandidates.count)

        let orderedCandidates = baseCandidates.sorted(by: { shouldPlaceBefore($0, $1, baseCoverageDepth: baseCoverageDepth) }) +
            detailCandidates.sorted(by: { shouldPlaceBefore($0, $1, baseCoverageDepth: baseCoverageDepth) })

        for candidate in orderedCandidates {
            guard let allocation = allocate(candidate: candidate,
                                            baseCoverageDepth: baseCoverageDepth,
                                            pages: &pages) else {
                skippedAllocationCount += 1
                continue
            }

            if allocation.atlasDepth != desiredDepth(for: candidate) {
                downgradedAllocationCount += 1
            }
            allocations.append(allocation)
        }

        return GlobeAtlasPlan(allocations: allocations,
                              pageSummaries: pages.map(\.summary),
                              downgradedAllocationCount: downgradedAllocationCount,
                              skippedAllocationCount: skippedAllocationCount)
    }

    private func shouldPlaceBefore(_ lhs: GlobeAtlasCandidate,
                                   _ rhs: GlobeAtlasCandidate,
                                   baseCoverageDepth: GlobeAtlasSlotDepth) -> Bool {
        let lhsDepth = preferredDepth(for: lhs, baseCoverageDepth: baseCoverageDepth)
        let rhsDepth = preferredDepth(for: rhs, baseCoverageDepth: baseCoverageDepth)
        if lhsDepth != rhsDepth {
            return lhsDepth < rhsDepth
        }
        if lhs.isFallback != rhs.isFallback {
            return lhs.isFallback
        }
        if lhs.screenDemandPx != rhs.screenDemandPx {
            return lhs.screenDemandPx > rhs.screenDemandPx
        }
        if lhs.distanceToCamera != rhs.distanceToCamera {
            return lhs.distanceToCamera < rhs.distanceToCamera
        }
        return lhs.placementIndex < rhs.placementIndex
    }

    private func allocate(candidate: GlobeAtlasCandidate,
                          baseCoverageDepth: GlobeAtlasSlotDepth,
                          pages: inout [Page]) -> GlobeAtlasAllocation? {
        let preferredDepth = preferredDepth(for: candidate, baseCoverageDepth: baseCoverageDepth)
        for depth in GlobeAtlasSlotDepth.allCases where depth.rawValue >= preferredDepth.rawValue {
            if let allocation = allocate(candidate: candidate, depth: depth, pages: &pages) {
                return allocation
            }
        }
        return nil
    }

    private func allocate(candidate: GlobeAtlasCandidate,
                          depth: GlobeAtlasSlotDepth,
                          pages: inout [Page]) -> GlobeAtlasAllocation? {
        for index in pages.indices {
            if let placedPosition = pages[index].add(depth: depth) {
                pages[index].allocatedSlotCount += 1
                return GlobeAtlasAllocation(candidate: candidate,
                                            pageIndex: pages[index].pageIndex,
                                            placedPosition: placedPosition,
                                            atlasDepth: depth,
                                            cellSizePx: depth.cellSize(pageSizePx: pageSizePx))
            }
        }

        guard pages.count < maxPageCount else { return nil }

        let page = Page(pageIndex: pages.count)
        pages.append(page)
        guard let placedPosition = pages[pages.count - 1].add(depth: depth) else {
            return nil
        }
        pages[pages.count - 1].allocatedSlotCount += 1
        return GlobeAtlasAllocation(candidate: candidate,
                                    pageIndex: page.pageIndex,
                                    placedPosition: placedPosition,
                                    atlasDepth: depth,
                                    cellSizePx: depth.cellSize(pageSizePx: pageSizePx))
    }

    private func totalSlotCapacity(at depth: GlobeAtlasSlotDepth) -> Int {
        let slotsPerAxis = 1 << Int(depth.rawValue)
        return maxPageCount * slotsPerAxis * slotsPerAxis
    }

    private func coverageDepth(candidateCount: Int) -> GlobeAtlasSlotDepth {
        guard candidateCount > 0 else { return .depth0 }
        for depth in GlobeAtlasSlotDepth.allCases {
            if totalSlotCapacity(at: depth) >= candidateCount {
                return depth
            }
        }
        return .depth4
    }

    private func desiredDepth(for candidate: GlobeAtlasCandidate) -> GlobeAtlasSlotDepth {
        guard qualityScale != 1.0 else { return candidate.desiredDepth }
        return GlobeAtlasSlotDepth.desired(forScreenDemandPx: candidate.screenDemandPx,
                                           pageSizePx: pageSizePx,
                                           qualityScale: qualityScale)
    }

    private func preferredDepth(for candidate: GlobeAtlasCandidate,
                                baseCoverageDepth: GlobeAtlasSlotDepth) -> GlobeAtlasSlotDepth {
        guard candidate.layer == .detail else {
            return baseCoverageDepth
        }
        return desiredDepth(for: candidate)
    }

    private func estimateScreenFootprint(placeTile: PlaceTile,
                                         frameContext: FrameContext) -> ScreenFootprint? {
        let viewport = SIMD2<Float>(Float(frameContext.drawSize.width),
                                    Float(frameContext.drawSize.height))
        let cameraUniform = frameContext.cameraUniform
        let constants = GlobeAtlasProjectionConstants(globe: frameContext.globeRenderUniform)
        var minimumX = Float.greatestFiniteMagnitude
        var minimumY = Float.greatestFiniteMagnitude
        var maximumX = -Float.greatestFiniteMagnitude
        var maximumY = -Float.greatestFiniteMagnitude
        var minimumDepth = Float.greatestFiniteMagnitude
        var hasVisibleSample = false

        for uv in Self.sampleUVs {
            let input = TilePointInput(uv: uv,
                                       tile: tileVector(placeTile.placeIn.tile))
            let projection = globeProjectTileUV(input: input,
                                                cameraUniform: cameraUniform,
                                                constants: constants)
            var output = screenPointFromClip(clip: projection.clip,
                                             viewportSize: viewport)
            guard output.visible != 0,
                  output.position.x.isFinite,
                  output.position.y.isFinite,
                  output.depth.isFinite else {
                continue
            }

            if output.visible != 0 {
                let visibility = globeProjectionVisibility(worldPosition: projection.worldPosition,
                                                           cameraUniform: cameraUniform,
                                                           constants: constants)
                output.visible = visibility.visible ? output.visible : 0
            }
            guard output.visible != 0 else {
                continue
            }

            let clampedPosition = clampToViewport(output.position, viewportSize: viewport)
            minimumX = min(minimumX, clampedPosition.x)
            minimumY = min(minimumY, clampedPosition.y)
            maximumX = max(maximumX, clampedPosition.x)
            maximumY = max(maximumY, clampedPosition.y)
            minimumDepth = min(minimumDepth, output.depth)
            hasVisibleSample = true
        }

        guard hasVisibleSample else {
            return nil
        }

        guard maximumX > minimumX || maximumY > minimumY else {
            let bounds = CGRect(x: CGFloat(minimumX),
                                y: CGFloat(minimumY),
                                width: 1,
                                height: 1)
            return ScreenFootprint(bounds: bounds,
                                   minimumDepth: minimumDepth)
        }

        let width = maximumX - minimumX
        let height = maximumY - minimumY
        guard width.isFinite, height.isFinite else {
            return nil
        }

        let bounds = CGRect(x: CGFloat(minimumX),
                            y: CGFloat(minimumY),
                            width: CGFloat(width),
                            height: CGFloat(height))
        return ScreenFootprint(bounds: bounds,
                               minimumDepth: minimumDepth)
    }

    private func tileVector(_ tile: Tile) -> SIMD3<Int32> {
        SIMD3<Int32>(Int32(tile.x), Int32(tile.y), Int32(tile.z))
    }

    private func clampToViewport(_ position: SIMD2<Float>,
                                 viewportSize: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2<Float>(simd_clamp(position.x, 0, viewportSize.x),
                     simd_clamp(position.y, 0, viewportSize.y))
    }

    private func screenPointFromClip(clip: SIMD4<Float>,
                                     viewportSize: SIMD2<Float>) -> ScreenPointOutput {
        guard clip.w > 0.0 else {
            return ScreenPointOutput(position: .zero,
                                     depth: 0.0,
                                     visible: 0,
                                     visibilityAlpha: 0.0)
        }

        let ndc = SIMD2<Float>(clip.x, clip.y) / clip.w
        let depth = clip.z / clip.w
        let position = (ndc * 0.5 + 0.5) * viewportSize
        return ScreenPointOutput(position: position,
                                 depth: depth,
                                 visible: 1,
                                 visibilityAlpha: 1.0)
    }

    private func globeProjectTileUV(input: TilePointInput,
                                    cameraUniform: CameraUniform,
                                    constants: GlobeAtlasProjectionConstants) -> GlobeAtlasProjectionResult {
        let zPow = powf(2.0, Float(input.tile.z))
        let size = 1.0 / zPow
        let vertexUvX = input.uv.x / zPow + size * Float(input.tile.x)
        let mercatorV = (Float(input.tile.y) + input.uv.y) / zPow
        let latitudeAtUv = atan(sinh(Float.pi * (1.0 - 2.0 * mercatorV)))
        let longitudeAtUv = vertexUvX * (2.0 * Float.pi) - Float.pi
        return globeProjectLatLon(latitude: latitudeAtUv,
                                  longitude: longitudeAtUv,
                                  cameraUniform: cameraUniform,
                                  constants: constants)
    }

    private func globeProjectLatLon(latitude: Float,
                                    longitude: Float,
                                    cameraUniform: CameraUniform,
                                    constants: GlobeAtlasProjectionConstants) -> GlobeAtlasProjectionResult {
        let sphereWorldPosition = constants.rotatedSphereWorldPosition(latitude: latitude,
                                                                       longitude: longitude)
        let flatWorldPosition = constants.flatWorldPosition(latitude: latitude,
                                                            longitude: longitude)
        let transition = constants.globe.transition
        let worldPosition = sphereWorldPosition + (flatWorldPosition - sphereWorldPosition) * transition
        let clip = cameraUniform.matrix * SIMD4<Float>(worldPosition, 1.0)
        return GlobeAtlasProjectionResult(clip: clip,
                                          worldPosition: worldPosition)
    }

    private func globeProjectionVisibility(worldPosition: SIMD3<Float>,
                                           cameraUniform: CameraUniform,
                                           constants: GlobeAtlasProjectionConstants) -> (visible: Bool, alpha: Float) {
        let globeCenter = SIMD3<Float>(0.0, 0.0, -constants.globe.radius)
        let toCamera = cameraUniform.eye - globeCenter
        if simd_length(toCamera) <= 0.0 || constants.globe.transition >= 0.95 {
            return (true, 1.0)
        }

        let toCameraLength = simd_length(toCamera)
        let radius = max(constants.globe.radius, 1e-6)
        let dotToCamera = simd_dot(worldPosition - globeCenter, toCamera)
        let normalization = max(toCameraLength * radius, 1e-6)
        let normalizedDot = dotToCamera / normalization
        let normalizedThreshold = constants.horizonThreshold / normalization
        let visibilityDelta = normalizedDot - normalizedThreshold

        if visibilityDelta <= -Self.globeHorizonFadeBandWidth {
            return (false, 0.0)
        }

        let alpha = smoothstep(edge0: -Self.globeHorizonFadeBandWidth,
                               edge1: Self.globeHorizonFadeBandWidth,
                               x: visibilityDelta)
        return (true, alpha)
    }

    private func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = simd_clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    }

    private static let globeHorizonFadeBandWidth: Float = 0.03

    private static let sampleUVs: [SIMD2<Float>] = [
        SIMD2<Float>(0.0, 0.0), SIMD2<Float>(0.5, 0.0), SIMD2<Float>(1.0, 0.0),
        SIMD2<Float>(0.0, 0.5), SIMD2<Float>(0.5, 0.5), SIMD2<Float>(1.0, 0.5),
        SIMD2<Float>(0.0, 1.0), SIMD2<Float>(0.5, 1.0), SIMD2<Float>(1.0, 1.0)
    ]
}

private struct ScreenFootprint {
    let bounds: CGRect
    let minimumDepth: Float
}

private struct GlobeAtlasProjectionResult {
    let clip: SIMD4<Float>
    let worldPosition: SIMD3<Float>
}

private struct GlobeAtlasProjectionConstants {
    let globe: GlobeUniform
    let panLatitude: Float
    let panLongitude: Float
    let mapSize: Float
    let panMercatorY: Float
    let rotationMatrix: matrix_float4x4
    let horizonThreshold: Float

    init(globe: GlobeUniform) {
        self.globe = globe
        let maxLatitude = Float(ImmersiveMapProjection.maxMercatorLatitude)
        self.panLatitude = globe.panY * maxLatitude
        self.panLongitude = globe.panX * .pi
        let distortion = cos(panLatitude)
        let mapSizeScale = (1.0 - globe.transition) * distortion + globe.transition
        self.mapSize = 2.0 * .pi * globe.radius * mapSizeScale
        self.panMercatorY = Float(ImmersiveMapProjection.yMercatorNormalized(latitude: Double(panLatitude)))
        self.rotationMatrix = GlobeAtlasProjectionConstants.makeRotationMatrix(panLatitude: panLatitude,
                                                                               panLongitude: panLongitude)
        let horizonFade = GlobeAtlasProjectionConstants.smoothstep(edge0: 0.8,
                                                                   edge1: 0.95,
                                                                   x: globe.transition)
        self.horizonThreshold = (1.0 - horizonFade) * (globe.radius * globe.radius) + horizonFade * -1e6
    }

    func rotatedSphereWorldPosition(latitude: Float,
                                    longitude: Float) -> SIMD3<Float> {
        let phi = latitude - (.pi * 0.5)
        let theta = longitude + .pi

        let x = globe.radius * sin(phi) * sin(theta)
        let y = globe.radius * cos(phi)
        let z = globe.radius * sin(phi) * cos(theta)
        let rotatedPosition = simd_transpose(rotationMatrix) * SIMD4<Float>(x, y, z, 1.0)
        return SIMD3<Float>(rotatedPosition.x,
                            rotatedPosition.y,
                            rotatedPosition.z - globe.radius)
    }

    func flatWorldPosition(latitude: Float,
                           longitude: Float) -> SIMD3<Float> {
        let normalizedWorldX = (longitude + .pi) / (2.0 * .pi)
        let mercatorY = Float(ImmersiveMapProjection.yMercatorNormalized(latitude: Double(latitude)))
        let halfMapSize = mapSize * 0.5
        let flatX = Float(ImmersiveMapProjection.wrap(value: Double(normalizedWorldX * mapSize - halfMapSize + globe.panX * halfMapSize),
                                                      size: Double(mapSize)))
        let flatY = (mercatorY - panMercatorY) * halfMapSize
        return SIMD3<Float>(flatX, flatY, 0.0)
    }

    private static func makeRotationMatrix(panLatitude: Float,
                                           panLongitude: Float) -> matrix_float4x4 {
        let cx = cos(-panLatitude)
        let sx = sin(-panLatitude)
        let cy = cos(-panLongitude)
        let sy = sin(-panLongitude)

        return matrix_float4x4(columns: (
            SIMD4<Float>(cy, 0, -sy, 0),
            SIMD4<Float>(sy * sx, cx, cy * sx, 0),
            SIMD4<Float>(sy * cx, -sx, cy * cx, 0),
            SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    private static func smoothstep(edge0: Float,
                                   edge1: Float,
                                   x: Float) -> Float {
        let t = simd_clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)
    }
}

private struct Page {
    let pageIndex: Int
    var tree = GlobeTileTextureTree()
    var allocatedSlotCount = 0

    var summary: GlobeAtlasPageSummary {
        GlobeAtlasPageSummary(pageIndex: pageIndex,
                              allocatedSlotCount: allocatedSlotCount)
    }

    mutating func add(depth: GlobeAtlasSlotDepth) -> PlacedPos? {
        tree.addNewValue(value: TextureValue(), depth: depth.rawValue)
    }
}
