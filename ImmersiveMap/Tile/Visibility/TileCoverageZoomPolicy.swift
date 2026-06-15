// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct TileCoverageZoomPlan: Equatable {
    let baseZoom: Int
    let detailZoom: Int?
}

enum TileCoverageZoomPolicy {
    static func resolve(cameraZoom: Double,
                        renderSurfaceMode _: ViewMode,
                        maximumZoomLevel: Int) -> TileCoverageZoomPlan {
        let baseZoom = min(max(0, Int(cameraZoom)), maximumZoomLevel)
        return TileCoverageZoomPlan(baseZoom: baseZoom, detailZoom: nil)
    }
}
