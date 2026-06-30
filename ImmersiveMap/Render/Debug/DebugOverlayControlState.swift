// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct DebugOverlayControlSnapshot: Equatable {
    let axesEnabled: Bool
    let tileLayersEnabled: Bool
    let wireframeEnabled: Bool
    let terrainEnabled: Bool
}

final class DebugOverlayControlState {
    private let lock = NSLock()
    private var axesEnabled = false
    private var tileLayersEnabled = false
    private var wireframeEnabled = false
    private var terrainEnabled = true

    func snapshot() -> DebugOverlayControlSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return DebugOverlayControlSnapshot(axesEnabled: axesEnabled,
                                           tileLayersEnabled: tileLayersEnabled,
                                           wireframeEnabled: wireframeEnabled,
                                           terrainEnabled: terrainEnabled)
    }

    func setAxesEnabled(_ isEnabled: Bool) {
        lock.lock()
        axesEnabled = isEnabled
        lock.unlock()
    }

    func setTileLayersEnabled(_ isEnabled: Bool) {
        lock.lock()
        tileLayersEnabled = isEnabled
        lock.unlock()
    }

    func setWireframeEnabled(_ isEnabled: Bool) {
        lock.lock()
        wireframeEnabled = isEnabled
        lock.unlock()
    }

    func setTerrainEnabled(_ isEnabled: Bool) {
        lock.lock()
        terrainEnabled = isEnabled
        lock.unlock()
    }
}
