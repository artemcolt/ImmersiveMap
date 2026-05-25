//
//  TileRenderStore.swift
//  TucikMap
//
//  Created by Artem on 6/6/25.
//

import Foundation
import MetalKit

final class TileRenderStore {
    struct TileRequestResult {
        let readyTilesBySource: [Tile: MetalTile?]
        let readyTilesCount: Int
        let requestedTilesCount: Int
    }

    private var mapNeedsTile: MapNeedsTile?
    private var memoryMetalTile: MemoryMetalTileCache!
    private let preparedDataBuilder: TilePreparedDataBuilder
    private let metalTileFactory: MetalTileFactory
    
    private weak var renderer: Renderer?
    
    func initRenderer(_ renderer: Renderer) {
        self.renderer = renderer
    }

    init(
        mapStyle: MapStyle,
        metalDevice: MTLDevice,
        textRenderer: TextRenderer,
        config: MapSettings
    ) {
        let preparedTileCacheIdentity = PreparedTileCacheIdentity(
            preparedFormatVersion: PreparedTileDiskCaching.preparedFormatVersion,
            styleRevision: mapStyle.preparedTileStyleRevision,
            flatSeparateRoadRenderingMinimumZoom: UInt32(max(0, config.style.flatSeparateRoadRenderingMinimumZoom)),
            textRevision: textRenderer.preparedTileTextRevision,
            labelLanguage: config.labels.language,
            houseNumbersEnabled: config.labels.houseNumbers.enabled,
            houseNumbersMinimumZoom: UInt32(max(0, config.labels.houseNumbers.minimumZoom)),
            capitalMaximumZoom: UInt32(max(0, config.labels.settlementVisibility.capitalMaximumZoom)),
            cityMaximumZoom: UInt32(max(0, config.labels.settlementVisibility.cityMaximumZoom)),
            smallSettlementMaximumZoom: UInt32(max(0, config.labels.settlementVisibility.smallSettlementMaximumZoom)),
            landmarkMinimumZoom: UInt32(max(0, config.labels.landmarks.minimumZoom)),
            addTestBorders: config.tiles.parsing.addTestBorders
        )
        let determineFeatureStyle = DetermineFeatureStyle(mapStyle: mapStyle)
        let tileParser = TileMvtParser(determineFeatureStyle: determineFeatureStyle, config: config)
        let textLabelsBuilder = TileTextLabelsBuilder(textRenderer: textRenderer)
        let roadLabelsBuilder = TileRoadLabelsBuilder(textRenderer: textRenderer)
        self.preparedDataBuilder = TilePreparedDataBuilder(tileParser: tileParser,
                                                           textLabelsBuilder: textLabelsBuilder,
                                                           roadLabelsBuilder: roadLabelsBuilder)
        self.metalTileFactory = MetalTileFactory(metalDevice: metalDevice)
        let maxCachedTilesMemory = config.tiles.cache.memoryCacheSizeInBytes
        memoryMetalTile = MemoryMetalTileCache(maxCacheSizeInBytes: maxCachedTilesMemory)
        mapNeedsTile = MapNeedsTile(tileRenderStore: self,
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

            renderer?.newTileAvailable(tile: preparedTile.tile)
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
