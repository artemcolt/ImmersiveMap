// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

final class RenderModeController {
    private(set) var projectionPolicy: ProjectionPolicy

    init(initialProjectionPolicy: ProjectionPolicy = .automatic) {
        projectionPolicy = initialProjectionPolicy
    }

    func advanceProjectionPolicy(currentResolvedPresentation: ResolvedPresentationState) {
        switch projectionPolicy {
        case .automatic:
            switch currentResolvedPresentation.renderBackendMode {
            case .spherical:
                projectionPolicy = .forcedFlat
            case .flat:
                projectionPolicy = .forcedGlobe
            }
        case .forcedGlobe, .forcedFlat:
            projectionPolicy = .automatic
        }
    }

}
