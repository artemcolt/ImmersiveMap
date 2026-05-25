//
//  ImmersiveMapView.swift
//  ImmersiveMapFramework
//  Created by Artem on 8/31/25.
//

import SwiftUI
import UIKit // For UIView

public struct ImmersiveMapView: UIViewRepresentable {
    private let settings: MapSettings
    private let avatarsController: AvatarsController
    private let cameraPosition: ImmersiveMapCameraPosition?
    private let cameraController: MapCameraController?
    private let selectionController: MapSelectionController?
    private let visibilityPolicy: VisibilityPolicy

    public init(settings: MapSettings = .default,
                avatarsController: AvatarsController = AvatarsController(),
                cameraPosition: ImmersiveMapCameraPosition? = nil,
                cameraController: MapCameraController? = nil,
                selectionController: MapSelectionController? = nil,
                visibilityPolicy: VisibilityPolicy = .followPresentation) {
        self.settings = settings
        self.avatarsController = avatarsController
        self.cameraPosition = cameraPosition
        self.cameraController = cameraController
        self.selectionController = selectionController
        self.visibilityPolicy = visibilityPolicy
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public func makeUIView(context: Context) -> ImmersiveMapUIView {
        let uiView = ImmersiveMapUIView(frame: .zero,
                                        settings: settings,
                                        avatarsController: avatarsController,
                                        cameraPosition: cameraPosition,
                                        visibilityPolicy: visibilityPolicy)
        context.coordinator.lastCameraPosition = cameraPosition
        context.coordinator.lastVisibilityPolicy = visibilityPolicy
        context.coordinator.updateAttachments(cameraController: cameraController,
                                              selectionController: selectionController,
                                              view: uiView)
        return uiView
    }
    
    public func updateUIView(_ uiView: ImmersiveMapUIView, context: Context) {
        uiView.applySettings(settings)
        context.coordinator.updateAttachments(cameraController: cameraController,
                                              selectionController: selectionController,
                                              view: uiView)
        if context.coordinator.lastVisibilityPolicy != visibilityPolicy {
            uiView.setVisibilityPolicy(visibilityPolicy)
            context.coordinator.lastVisibilityPolicy = visibilityPolicy
        }
        if context.coordinator.lastCameraPosition != cameraPosition {
            uiView.setCameraPosition(cameraPosition)
            context.coordinator.lastCameraPosition = cameraPosition
        }
    }

    public static func dismantleUIView(_ uiView: ImmersiveMapUIView, coordinator: Coordinator) {
        _ = uiView
        coordinator.detach()
    }

    public final class Coordinator {
        fileprivate var lastCameraPosition: ImmersiveMapCameraPosition?
        fileprivate var lastVisibilityPolicy: VisibilityPolicy?
        private weak var attachedCameraController: MapCameraController?
        private weak var attachedSelectionController: MapSelectionController?
        private weak var attachedView: ImmersiveMapUIView?

        @MainActor
        fileprivate func updateAttachments(cameraController: MapCameraController?,
                                           selectionController: MapSelectionController?,
                                           view: ImmersiveMapUIView) {
            guard attachedCameraController !== cameraController
                || attachedSelectionController !== selectionController
                || attachedView !== view else {
                return
            }

            attachedCameraController?.attach(mapView: nil)
            attachedSelectionController?.attach(mapView: nil)
            attachedCameraController = cameraController
            attachedSelectionController = selectionController
            attachedView = view
            cameraController?.attach(mapView: view)
            selectionController?.attach(mapView: view)
        }

        @MainActor
        fileprivate func detach() {
            attachedCameraController?.attach(mapView: nil)
            attachedSelectionController?.attach(mapView: nil)
            attachedCameraController = nil
            attachedSelectionController = nil
            attachedView = nil
        }
    }
}
