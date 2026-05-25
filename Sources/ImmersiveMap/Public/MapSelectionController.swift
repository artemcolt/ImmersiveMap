//
//  MapSelectionController.swift
//  ImmersiveMapFramework
//

import CoreGraphics
import Foundation

public struct MapSelection: Equatable {
    public enum Kind: String {
        case avatar
    }

    public let kind: Kind
    public let objectID: UInt64

    public init(kind: Kind, objectID: UInt64) {
        self.kind = kind
        self.objectID = objectID
    }
}

public enum MapSelectionSource: String {
    case tap
    case programmatic
    case system
}

public struct MapSelectionChangeEvent: Equatable {
    public let selection: MapSelection
    public let source: MapSelectionSource
    public let screenPoint: CGPoint?

    public init(selection: MapSelection,
                source: MapSelectionSource,
                screenPoint: CGPoint?) {
        self.selection = selection
        self.source = source
        self.screenPoint = screenPoint
    }
}

public struct MapSelectionClearEvent: Equatable {
    public let previousSelection: MapSelection
    public let source: MapSelectionSource
    public let screenPoint: CGPoint?

    public init(previousSelection: MapSelection,
                source: MapSelectionSource,
                screenPoint: CGPoint?) {
        self.previousSelection = previousSelection
        self.source = source
        self.screenPoint = screenPoint
    }
}

@MainActor
public final class MapSelectionController {
    private weak var mapView: ImmersiveMapUIView?

    public var onSelectionChanged: ((MapSelectionChangeEvent) -> Void)?
    public var onSelectionCleared: ((MapSelectionClearEvent) -> Void)?
    public var onMapBackgroundTap: ((CGPoint) -> Void)?

    public init() {}

    public func currentSelection() -> MapSelection? {
        mapView?.currentMapSelection()
    }

    @discardableResult
    public func select(_ selection: MapSelection) -> Bool {
        mapView?.selectMapSelection(selection,
                                    source: .programmatic,
                                    screenPoint: nil) ?? false
    }

    @discardableResult
    public func clearSelection() -> Bool {
        mapView?.clearMapSelection(source: .programmatic,
                                   screenPoint: nil) ?? false
    }

    public func attach(mapView: ImmersiveMapUIView?) {
        self.mapView?.attach(selectionController: nil)
        self.mapView = mapView
        mapView?.attach(selectionController: self)
    }

    func notifySelectionChanged(_ event: MapSelectionChangeEvent) {
        onSelectionChanged?(event)
    }

    func notifySelectionCleared(_ event: MapSelectionClearEvent) {
        onSelectionCleared?(event)
    }

    func notifyMapBackgroundTap(at point: CGPoint) {
        onMapBackgroundTap?(point)
    }
}
