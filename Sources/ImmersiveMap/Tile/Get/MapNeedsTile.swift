//
//  MapNeedsTile.swift
//  TucikMap
//
//  Created by Artem on 5/30/25.
//

import Foundation
import MetalKit

// Бизнес-назначение:
// Оркестратор загрузки тайлов для текущего кадра карты.
// Принимает актуальный набор нужных тайлов, отменяет устаревшие in-flight задачи,
// ограничивает параллелизм, ставит отложенные запросы в deduplicated FIFO и запускает
// загрузку/парс через `TileLoadPipeline`.
// Решения о том, когда запрос тайла временно блокируется после ошибок, делегируются
// в `TileRetryController` (per-tile backoff + глобальный cooldown).
class MapNeedsTile {
    typealias RetryPolicy = TileRetryController.Policy

    private var ongoingTasks: [Tile: Task<Void, Never>] = [:]
    private let maxConcurrentFetches: Int
    private let pendingTilesQueue: DeduplicatedTilesFIFO
    private var wantedTiles: Set<Tile> = []
    private let loadPipeline: TileLoadPipeline
    private let retryController: TileRetryController
    private let stateQueue = DispatchQueue(label: "ImmersiveMapFramework.MapNeedsTile.state")
    
    // Production-конструктор: собирает стандартный pipeline (диск + сеть + парс в TileRenderStore).
    convenience init(tileRenderStore: TileRenderStore,
                     config: MapSettings,
                     preparedTileCacheIdentity: PreparedTileCacheIdentity) {
        self.init(config: config,
                  loadPipeline: DefaultTileLoadPipeline(tileRenderStore: tileRenderStore,
                                                        config: config,
                                                        preparedTileCacheIdentity: preparedTileCacheIdentity))
    }

    // Базовый конструктор с явной инъекцией pipeline/политики (используется и в тестах).
    init(config: MapSettings,
         loadPipeline: TileLoadPipeline,
         retryPolicy: RetryPolicy = .default,
         now: @escaping () -> Date = Date.init) {
        self.maxConcurrentFetches = config.tiles.network.maxConcurrentFetches
        self.pendingTilesQueue = DeduplicatedTilesFIFO(capacity: config.tiles.network.pendingRequestQueueCapacity)
        self.loadPipeline = loadPipeline
        self.retryController = TileRetryController(policy: retryPolicy, now: now)
    }
    
    // Обновляет актуальный набор тайлов для кадра: отменяет stale-задачи, очищает pending-очередь
    // и заново планирует загрузку нужных тайлов в приоритетном порядке.
    func request(tiles: [Tile]) {
        // Дедупликация с сохранением исходного порядка `tiles`: порядок важен для приоритета загрузки.
        // Отдельный `wanted` как Set нужен для O(1) проверок актуальности тайла (contains) и отмены stale-задач.
        var deduplicatedTiles: [Tile] = []
        deduplicatedTiles.reserveCapacity(tiles.count)
        var seenTiles: Set<Tile> = []
        for tile in tiles {
            if seenTiles.insert(tile).inserted {
                deduplicatedTiles.append(tile)
            }
        }
        let wanted = Set(deduplicatedTiles)

        stateQueue.sync {
            wantedTiles = wanted

            let staleTiles = ongoingTasks.keys.filter { wantedTiles.contains($0) == false }
            for tile in staleTiles {
                ongoingTasks[tile]?.cancel()
                ongoingTasks.removeValue(forKey: tile)
            }

            pendingTilesQueue.clear()
            retryController.retainOnly(tiles: wantedTiles)

            // Планируем весь batch внутри одного lock, чтобы не делать sync на каждый тайл.
            for tile in deduplicatedTiles {
                requestSingleTileLocked(tile: tile)
            }
        }
    }
    
    // Внутренняя версия планирования без lock-обертки.
    // Должна вызываться только изнутри `stateQueue`.
    private func requestSingleTileLocked(tile: Tile) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        if wantedTiles.contains(tile) == false {
            return
        }
        if ongoingTasks[tile] != nil {
            return
        }
        if retryController.shouldBlock(tile: tile) {
            return
        }

        if ongoingTasks.count >= maxConcurrentFetches {
            pendingTilesQueue.enqueue(tile)
            return
        }

        createLoadTileTaskLocked(tile: tile)
    }

    // Создает async-задачу загрузки тайла и регистрирует ее как in-flight.
    // Должна вызываться только изнутри `stateQueue`.
    private func createLoadTileTaskLocked(tile: Tile) {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        let task = Task {
            await loadTile(tile: tile)
        }
        ongoingTasks[tile] = task
    }
    
    // Полный цикл загрузки тайла: prepared disk -> raw disk -> сеть -> подготовка -> materialize -> сохранение в кэш.
    // На любом этапе учитывает отмену задачи и обновляет retry-state по результату.
    private func loadTile(tile: Tile) async {
        if Task.isCancelled {
            return
        }
        defer {
            Task { @MainActor in
                finishLoading(tile: tile)
            }
        }
        if let preparedTile = await loadPipeline.requestPreparedDiskCached(tile: tile) {
            if Task.isCancelled {
                return
            }
            let materializedPreparedTile = await materializePreparedTile(preparedTile, expectedTile: tile)
            if Task.isCancelled {
                return
            }
            if materializedPreparedTile {
                markLoadSucceeded(tile: tile)
                return
            }
            loadPipeline.removePreparedFromDisk(tile: tile)
        }

        if let diskCachedData = await loadPipeline.requestDiskCached(tile: tile) {
            if Task.isCancelled {
                return
            }
            let preparedFromDisk = await prepareTile(data: diskCachedData, tile: tile)
            if Task.isCancelled {
                return
            }
            guard let preparedFromDisk else {
                loadPipeline.removeFromDisk(tile: tile)
                loadPipeline.removePreparedFromDisk(tile: tile)
                await proceedToNetwork(tile: tile)
                return
            }

            let materializedFromDisk = await materializePreparedTile(preparedFromDisk, expectedTile: tile)
            if Task.isCancelled {
                return
            }
            if materializedFromDisk {
                loadPipeline.savePreparedOnDisk(tile: tile, preparedTile: preparedFromDisk)
                markLoadSucceeded(tile: tile)
                return
            }
            loadPipeline.removeFromDisk(tile: tile)
            loadPipeline.removePreparedFromDisk(tile: tile)
        }

        await proceedToNetwork(tile: tile)
    }

    private func proceedToNetwork(tile: Tile) async {
        if Task.isCancelled {
            return
        }

        let downloadResult = await loadPipeline.download(tile: tile)
        if Task.isCancelled {
            return
        }

        switch downloadResult {
        case let .success(data):
            guard let preparedFromNetwork = await prepareTile(data: data, tile: tile) else {
                loadPipeline.removePreparedFromDisk(tile: tile)
                markLoadFailed(tile: tile, reason: .parseFailed)
                return
            }
            if Task.isCancelled {
                return
            }
            let materializedFromNetwork = await materializePreparedTile(preparedFromNetwork, expectedTile: tile)
            if Task.isCancelled {
                return
            }
            if materializedFromNetwork {
                loadPipeline.saveOnDisk(tile: tile, data: data)
                loadPipeline.savePreparedOnDisk(tile: tile, preparedTile: preparedFromNetwork)
                markLoadSucceeded(tile: tile)
            } else {
                loadPipeline.removePreparedFromDisk(tile: tile)
                markLoadFailed(tile: tile, reason: .parseFailed)
            }
        case let .failure(downloadFailure):
            markLoadFailed(tile: tile, reason: .download(downloadFailure))
        }
    }

    private func prepareTile(data: Data, tile: Tile) async -> PreparedTileCPU? {
        if Task.isCancelled {
            return nil
        }
        return await loadPipeline.prepare(tile: tile, data: data)
    }

    private func materializePreparedTile(_ preparedTile: PreparedTileCPU, expectedTile: Tile) async -> Bool {
        if Task.isCancelled {
            return false
        }
        guard preparedTile.tile == expectedTile else {
            return false
        }
        return await loadPipeline.materialize(preparedTile: preparedTile)
    }

    // Завершает in-flight загрузку тайла и пытается запустить следующий подходящий тайл из pending-очереди.
    @MainActor
    private func finishLoading(tile: Tile) {
        stateQueue.sync {
            ongoingTasks.removeValue(forKey: tile)

            while let popped = pendingTilesQueue.dequeue() {
                if wantedTiles.contains(popped), ongoingTasks[popped] == nil {
                    requestSingleTileLocked(tile: popped)
                    break
                }
            }
        }
    }

    // Полностью останавливает scheduler: очищает wanted/pending/retry-state и отменяет все in-flight задачи.
    func cancelAll() {
        stateQueue.sync {
            wantedTiles.removeAll()
            pendingTilesQueue.clear()
            retryController.reset()
            for task in ongoingTasks.values {
                task.cancel()
            }
            ongoingTasks.removeAll()
        }
    }

    // Фиксирует успешную загрузку тайла: сбрасывает retry-state для этого тайла.
    private func markLoadSucceeded(tile: Tile) {
        stateQueue.sync {
            retryController.registerSuccess(for: tile)
        }
    }

    // Фиксирует неуспешную загрузку тайла: обновляет backoff/cooldown через retry-контроллер.
    private func markLoadFailed(tile: Tile, reason: TileRetryFailureReason) {
        stateQueue.sync {
            retryController.registerFailure(for: tile, reason: reason)
        }
    }
}
