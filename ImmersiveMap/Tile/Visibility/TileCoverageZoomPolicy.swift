// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct TileCoverageZoomPlan: Equatable {
    let baseZoom: Int
    let detailZoom: Int?
}

enum TileCoverageZoomPolicy {
    static func resolve(cameraZoom: Double,
                        renderSurfaceMode: ViewMode,
                        maximumZoomLevel: Int) -> TileCoverageZoomPlan {
        let baseZoom = min(max(0, Int(cameraZoom)), maximumZoomLevel)
        guard renderSurfaceMode == .spherical else {
            return TileCoverageZoomPlan(baseZoom: baseZoom, detailZoom: nil)
        }

        let aheadZoom = min(maximumZoomLevel, max(baseZoom, Int(ceil(cameraZoom)) + 1))
        let detailZoom = aheadZoom > baseZoom ? aheadZoom : nil
        return TileCoverageZoomPlan(baseZoom: baseZoom, detailZoom: detailZoom)
    }
}
