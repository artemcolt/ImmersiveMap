// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

@testable import ImmersiveMap
import Foundation
import XCTest

final class ImmersiveMapNeedsTileTests: XCTestCase {
    func testRequestKeepsInFlightTileWhenItTemporarilyLeavesDemand() async {
        var settings = ImmersiveMapSettings.default
        settings.tiles.network.maxConcurrentFetches = 1
        let pipeline = ControlledTileLoadPipeline()
        let loader = ImmersiveMapNeedsTile(config: settings, loadPipeline: pipeline)
        let firstTile = Tile(x: 1, y: 1, z: 4)
        let secondTile = Tile(x: 2, y: 1, z: 4)

        loader.request(tiles: [firstTile])
        let firstTileStarted = await pipeline.waitUntilStarted(firstTile)
        XCTAssertTrue(firstTileStarted)

        loader.request(tiles: [secondTile])
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(pipeline.wasCanceled(firstTile))
        XCTAssertFalse(pipeline.hasStarted(secondTile))

        pipeline.completeDownload(firstTile, result: .failure(.network))
        let secondTileStarted = await pipeline.waitUntilStarted(secondTile)
        XCTAssertTrue(secondTileStarted)

        pipeline.completeDownload(secondTile, result: .failure(.network))
    }
}

private final class ControlledTileLoadPipeline: TileLoadPipeline {
    private let lock = NSLock()
    private var startedTiles: Set<Tile> = []
    private var canceledTiles: Set<Tile> = []
    private var downloadContinuations: [Tile: CheckedContinuation<TileDownloader.DownloadResult, Never>] = [:]

    func requestPreparedDiskCached(tile _: Tile) async -> PreparedTileCPU? {
        nil
    }

    func requestDiskCached(tile _: Tile) async -> Data? {
        nil
    }

    func download(tile: Tile) async -> TileDownloader.DownloadResult {
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                recordDownloadStarted(tile: tile, continuation: continuation)
            }
        }, onCancel: {
            recordDownloadCanceled(tile)
        })
    }

    func savePreparedOnDisk(tile _: Tile, preparedTile _: PreparedTileCPU) {}

    func saveOnDisk(tile _: Tile, data _: Data) {}

    func removePreparedFromDisk(tile _: Tile) {}

    func removeFromDisk(tile _: Tile) {}

    func prepare(tile _: Tile, data _: Data) async -> PreparedTileCPU? {
        nil
    }

    func materialize(preparedTile _: PreparedTileCPU) async -> Bool {
        false
    }

    func parse(tile _: Tile, data _: Data) async -> Bool {
        false
    }

    func hasStarted(_ tile: Tile) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return startedTiles.contains(tile)
    }

    func wasCanceled(_ tile: Tile) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return canceledTiles.contains(tile)
    }

    func completeDownload(_ tile: Tile, result: TileDownloader.DownloadResult) {
        let continuation: CheckedContinuation<TileDownloader.DownloadResult, Never>?
        lock.lock()
        continuation = downloadContinuations.removeValue(forKey: tile)
        lock.unlock()
        continuation?.resume(returning: result)
    }

    func waitUntilStarted(_ tile: Tile) async -> Bool {
        for _ in 0..<100 {
            if hasStarted(tile) {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }

    private func recordDownloadStarted(
        tile: Tile,
        continuation: CheckedContinuation<TileDownloader.DownloadResult, Never>
    ) {
        lock.lock()
        startedTiles.insert(tile)
        downloadContinuations[tile] = continuation
        lock.unlock()
    }

    private func recordDownloadCanceled(_ tile: Tile) {
        let continuation: CheckedContinuation<TileDownloader.DownloadResult, Never>?
        lock.lock()
        canceledTiles.insert(tile)
        continuation = downloadContinuations.removeValue(forKey: tile)
        lock.unlock()
        continuation?.resume(returning: .failure(.network))
    }
}
