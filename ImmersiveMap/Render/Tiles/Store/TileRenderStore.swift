// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation
import MetalKit

final class TileRenderStore {
    struct TileRequestResult {
        let readyTilesBySource: [Tile: MetalTile?]
        let readyTilesCount: Int
        let requestedTilesCount: Int
    }

    private var mapNeedsTile: ImmersiveMapNeedsTile?
    private var memoryMetalTile: MemoryMetalTileCache!
    private let preparedDataBuilder: TilePreparedDataBuilder
    private let metalTileFactory: MetalTileFactory

    weak var eventSink: RenderFrameEventSink?

    init(
        mapStyle: ImmersiveMapStyle,
        metalDevice: MTLDevice,
        textRenderer: TextRenderer,
        config: ImmersiveMapSettings
    ) {
        let preparedTileCacheIdentity = PreparedTileCacheIdentity(
            preparedFormatVersion: PreparedTileDiskCaching.preparedFormatVersion,
            styleRevision: mapStyle.preparedTileStyleRevision,
            tileSourceRevision: PreparedTileCacheIdentity.tileSourceRevision(for: config.tiles.network),
            flatSeparateRoadRenderingMinimumZoom: UInt32(max(0, config.style.flatSeparateRoadRenderingMinimumZoom)),
            textRevision: textRenderer.preparedTileTextRevision,
            labelLanguage: config.labels.language,
            labelFallbackPolicy: config.labels.fallbackPolicy,
            houseNumbersEnabled: config.labels.houseNumbers.enabled,
            houseNumbersMinimumZoom: UInt32(max(0, config.labels.houseNumbers.minimumZoom)),
            capitalMaximumZoom: UInt32(max(0, config.labels.settlementVisibility.capitalMaximumZoom)),
            cityMaximumZoom: UInt32(max(0, config.labels.settlementVisibility.cityMaximumZoom)),
            smallSettlementMaximumZoom: UInt32(max(0, config.labels.settlementVisibility.smallSettlementMaximumZoom)),
            landmarkMinimumZoom: UInt32(max(0, config.labels.landmarks.minimumZoom)),
            addTestBorders: config.tiles.parsing.addTestBorders
        )
        let determineFeatureStyle = DetermineFeatureStyle(mapStyle: mapStyle)
        let tileParser = TileMvtParser(determineFeatureStyle: determineFeatureStyle,
                                       config: config,
                                       glyphCoverage: textRenderer.glyphCoverage)
        let textLabelsBuilder = TileTextLabelsBuilder(textRenderer: textRenderer)
        let roadLabelsBuilder = TileRoadLabelsBuilder(textRenderer: textRenderer)
        self.preparedDataBuilder = TilePreparedDataBuilder(tileParser: tileParser,
                                                           textLabelsBuilder: textLabelsBuilder,
                                                           roadLabelsBuilder: roadLabelsBuilder)
        self.metalTileFactory = MetalTileFactory(metalDevice: metalDevice)
        let maxCachedTilesMemory = config.tiles.cache.memoryCacheSizeInBytes
        memoryMetalTile = MemoryMetalTileCache(maxCacheSizeInBytes: maxCachedTilesMemory)
        mapNeedsTile = ImmersiveMapNeedsTile(tileRenderStore: self,
                                    config: config,
                                    preparedTileCacheIdentity: preparedTileCacheIdentity)
    }
    
    func getMetalTile(tile: Tile) -> MetalTile? {
        return memoryMetalTile.getTile(forKey: tile)
    }
    
    func requestTiles(_ tiles: [Tile]) -> TileRequestResult {
        var readyTilesBySource: [Tile: MetalTile?] = [:]
        readyTilesBySource.reserveCapacity(tiles.count)
        var request: [Tile] = []
        var readyTilesCount = 0
        for tile in tiles {
            let metalTile = getMetalTile(tile: tile)
            
            // No ready tile to display; request it, load from disk or network
            // Also parse it and then store it in the cache
            if metalTile == nil {
                request.append(tile)
            } else {
                readyTilesCount += 1
            }
            
            // Keep tile availability for the caller.
            readyTilesBySource[tile] = metalTile
        }
        
        
        // Send all missing tiles for loading
        mapNeedsTile!.request(tiles: request)

        return TileRequestResult(readyTilesBySource: readyTilesBySource,
                                 readyTilesCount: readyTilesCount,
                                 requestedTilesCount: request.count)
    }

    func prepareTile(tile: Tile, data: Data) async -> PreparedTileCPU? {
        do {
            return try preparedDataBuilder.build(tile: tile, data: data)
        } catch {
            #if DEBUG
            print("[WARN] Failed to parse tile \(tile): \(error)")
            #endif
            return nil
        }
    }

    func materializePreparedTile(_ preparedTile: PreparedTileCPU) async -> Bool {
        let metalTile = metalTileFactory.makeTile(from: preparedTile)

        await MainActor.run {
            self.memoryMetalTile.setTileData(
                tile: metalTile,
                forKey: preparedTile.tile
            )

            eventSink?.invalidate(.tileAvailable)
        }
        return true
    }

    func parseTile(tile: Tile, data: Data) async -> Bool {
        guard let preparedTile = await prepareTile(tile: tile, data: data) else {
            return false
        }
        return await materializePreparedTile(preparedTile)
    }

    func handleMemoryWarning() {
        mapNeedsTile?.cancelAll()
        memoryMetalTile.removeAll()
    }

    func evict() {
        mapNeedsTile?.cancelAll()
        memoryMetalTile.removeAll()
    }
}
