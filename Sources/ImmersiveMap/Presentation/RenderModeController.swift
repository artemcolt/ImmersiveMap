//
//  RenderModeController.swift
//  ImmersiveMapFramework
//  Created by Artem on 3/10/26.
//

import Foundation

final class RenderModeController {
    private(set) var projectionPolicy: ProjectionPolicy
    private(set) var visibilityPolicy: VisibilityPolicy

    init(initialProjectionPolicy: ProjectionPolicy = .automatic,
         initialVisibilityPolicy: VisibilityPolicy = .followPresentation) {
        projectionPolicy = initialProjectionPolicy
        visibilityPolicy = initialVisibilityPolicy
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

    func setVisibilityPolicy(_ policy: VisibilityPolicy) {
        visibilityPolicy = policy
    }
}
