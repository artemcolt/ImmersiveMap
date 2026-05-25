//
//  BaseLabelRebuildState.swift
//  ImmersiveMapFramework
//  Created by Artem on 2/21/26.
//

final class BaseLabelRebuildState {
    struct Snapshot {
        // CPU staging array for base-label screen compute.
        // One element per label in current rebuild order:
        // tile UV anchor + source tile id + tile slot indirection id.
        // The same index is reused across runtime/collision buffers, so order must stay stable.
        let tilePointInputs: [TilePointInput]
        let baseLabelsDrawBatches: [LabelsDrawBatch]
        let runtimeMeta: [LabelRuntimeMeta]
    }

    func buildSnapshot(trackedPlaceTiles: [PlaceTileRetantionTracker.TrackedPlaceTile],
                       tileIndexAllocator: VisibleTileIndexAllocator) -> Snapshot {
        let sourceEntries = BaseLabelSourceEntry.build(from: trackedPlaceTiles)
        var tilePointInputs: [TilePointInput] = []
        var baseLabelsDrawBatches: [LabelsDrawBatch] = []
        // Per-label runtime flags used by collision and draw passes.
        var runtimeMeta: [LabelRuntimeMeta] = []
        var seenLabelKeys: Set<UInt64> = []

        for sourceEntry in sourceEntries {
            let metalTile = sourceEntry.metalTile
            let textLabels = metalTile.tileBuffers.textLabels
            guard textLabels.labelsCount > 0 else {
                continue
            }
            let tileSlotIndex = tileIndexAllocator.tileIndex(for: sourceEntry.ownerKey)
            let retainedFlag: UInt8 = sourceEntry.isRetained ? 1 : 0
            // Each input is a tile point where a label is anchored.
            // Collect one large contiguous array of these points across all tracked tiles for GPU passes.
            tilePointInputs.reserveCapacity(tilePointInputs.count + textLabels.placementInputs.count)
            runtimeMeta.reserveCapacity(runtimeMeta.count + textLabels.placementInputs.count)
            for label in textLabels.placementInputs {
                var input = label.pointInput
                input.tileSlotIndex = tileSlotIndex
                tilePointInputs.append(input)

                let meta = label.placementMeta
                let duplicateFlag: UInt8 = seenLabelKeys.contains(meta.key) ? 1 : 0
                runtimeMeta.append(LabelRuntimeMeta(duplicate: duplicateFlag,
                                                    isRetained: retainedFlag,
                                                    visibleTileIndex: 0,
                                                    labelSizePx: meta.labelSizePx))
                seenLabelKeys.insert(meta.key)
            }

            baseLabelsDrawBatches.append(LabelsDrawBatch(labelsByStyleRuns: textLabels.labelsByStyleRuns,
                                                         poiIconRuns: textLabels.poiIconRuns,
                                                         labelInstanceCount: textLabels.labelsCount))
        }

        return Snapshot(tilePointInputs: tilePointInputs,
                        baseLabelsDrawBatches: baseLabelsDrawBatches,
                        runtimeMeta: runtimeMeta)
    }
}
