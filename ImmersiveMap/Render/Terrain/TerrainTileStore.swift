// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import Metal

struct TerrainTileDrawItem {
    let visibleTile: VisibleTile
    let sourceTile: Tile
    let mesh: MetalTerrainMesh
}

final class TerrainTileStore {
    static let heightScale: Float = 1.0

    private let metalDevice: MTLDevice
    private let lock = NSLock()
    private var meshesByKey: [TerrainTileCacheKey: MetalTerrainMesh] = [:]
    private var inFlightTasksByKey: [TerrainTileCacheKey: Task<Void, Never>] = [:]

    weak var eventSink: RenderFrameEventSink?

    init(metalDevice: MTLDevice) {
        self.metalDevice = metalDevice
    }

    func requestVisibleTiles(_ visibleTiles: [VisibleTile],
                             terrain: ImmersiveMapSettings.TerrainSettings,
                             renderSurfaceMode: ViewMode,
                             globeRadius: Float) {
        guard let source = terrain.source else {
            return
        }

        let plans = TerrainTileRequestPlanner.drawPlans(visibleTiles: visibleTiles,
                                                        terrain: terrain,
                                                        renderSurfaceMode: renderSurfaceMode,
                                                        globeRadius: globeRadius,
                                                        heightScale: Self.heightScale)
        for plan in plans {
            request(plan: plan, source: source, terrain: terrain, globeRadius: globeRadius)
        }
    }

    func drawItems(visibleTiles: [VisibleTile],
                   terrain: ImmersiveMapSettings.TerrainSettings,
                   renderSurfaceMode: ViewMode,
                   globeRadius: Float) -> [TerrainTileDrawItem] {
        let plans = TerrainTileRequestPlanner.drawPlans(visibleTiles: visibleTiles,
                                                        terrain: terrain,
                                                        renderSurfaceMode: renderSurfaceMode,
                                                        globeRadius: globeRadius,
                                                        heightScale: Self.heightScale)
        var items: [TerrainTileDrawItem] = []
        items.reserveCapacity(plans.count)

        lock.lock()
        defer { lock.unlock() }
        for plan in plans {
            guard let mesh = meshesByKey[plan.cacheKey] else {
                continue
            }
            items.append(TerrainTileDrawItem(visibleTile: plan.visibleTile,
                                             sourceTile: plan.sourceTile,
                                             mesh: mesh))
        }
        return items
    }

    func handleMemoryWarning() {
        clear()
    }

    func evict() {
        clear()
    }

    private func request(plan: TerrainTileRequestPlan,
                         source: ImmersiveMapTerrainSource,
                         terrain: ImmersiveMapSettings.TerrainSettings,
                         globeRadius: Float) {
        lock.lock()
        if meshesByKey[plan.cacheKey] != nil || inFlightTasksByKey[plan.cacheKey] != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.load(plan: plan,
                            source: source,
                            terrain: terrain,
                            globeRadius: globeRadius)
        }

        lock.lock()
        if meshesByKey[plan.cacheKey] != nil || inFlightTasksByKey[plan.cacheKey] != nil {
            lock.unlock()
            task.cancel()
            return
        }
        inFlightTasksByKey[plan.cacheKey] = task
        lock.unlock()
    }

    private func load(plan: TerrainTileRequestPlan,
                      source: ImmersiveMapTerrainSource,
                      terrain: ImmersiveMapSettings.TerrainSettings,
                      globeRadius: Float) async {
        defer {
            finishRequest(for: plan.cacheKey)
        }

        let url = TerrainTileURLProvider(source: source).url(for: plan.sourceTile)
        guard let data = try? await fetchData(from: url),
              Task.isCancelled == false,
              let heightGrid = TerrainRGBDecoder.decode(data: data, encoding: source.encoding) else {
            return
        }

        let mesh = makeMesh(plan: plan,
                            heightGrid: heightGrid,
                            terrain: terrain,
                            globeRadius: globeRadius)
        guard Task.isCancelled == false,
              let metalMesh = await MainActor.run(body: { MetalTerrainMesh(device: metalDevice, mesh: mesh) }) else {
            return
        }

        await MainActor.run {
            self.store(metalMesh, for: plan.cacheKey)
            self.eventSink?.invalidate(.tileAvailable)
        }
    }

    private func fetchData(from url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private func makeMesh(plan: TerrainTileRequestPlan,
                          heightGrid: TerrainHeightGrid,
                          terrain: ImmersiveMapSettings.TerrainSettings,
                          globeRadius: Float) -> TerrainMesh {
        switch plan.cacheKey.renderSurfaceMode {
        case .flat:
            return TerrainMeshBuilder.buildFlatMesh(tile: plan.sourceTile,
                                                    heightGrid: heightGrid,
                                                    resolution: terrain.meshResolution,
                                                    exaggeration: terrain.exaggeration,
                                                    heightScale: Self.heightScale)
        case .spherical:
            return TerrainMeshBuilder.buildGlobeMesh(tile: plan.sourceTile,
                                                     heightGrid: heightGrid,
                                                     resolution: terrain.meshResolution,
                                                     globeRadius: globeRadius,
                                                     exaggeration: terrain.exaggeration,
                                                     heightScale: Self.heightScale)
        }
    }

    private func store(_ mesh: MetalTerrainMesh, for key: TerrainTileCacheKey) {
        lock.lock()
        meshesByKey[key] = mesh
        lock.unlock()
    }

    private func finishRequest(for key: TerrainTileCacheKey) {
        lock.lock()
        inFlightTasksByKey[key] = nil
        lock.unlock()
    }

    private func clear() {
        lock.lock()
        let tasks = Array(inFlightTasksByKey.values)
        inFlightTasksByKey.removeAll()
        meshesByKey.removeAll()
        lock.unlock()

        for task in tasks {
            task.cancel()
        }
    }
}
