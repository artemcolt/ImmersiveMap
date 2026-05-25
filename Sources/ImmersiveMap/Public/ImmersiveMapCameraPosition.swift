//
//  ImmersiveMapCameraPosition.swift
//  ImmersiveMapFramework
//

import Foundation
import CoreGraphics

public struct ImmersiveMapCameraPosition: Equatable, Sendable {
    public static let `default` = ImmersiveMapCameraPosition(latitudeDegrees: 0,
                                                             longitudeDegrees: 0,
                                                             zoom: 0,
                                                             bearing: 0,
                                                             pitch: 0)

    public let latitudeDegrees: Double
    public let longitudeDegrees: Double
    public let zoom: Double
    public let bearing: Float
    public let pitch: Float

    public init(latitudeDegrees: Double,
                longitudeDegrees: Double,
                zoom: Double,
                bearing: Float = 0,
                pitch: Float = 0) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.zoom = zoom
        self.bearing = bearing
        self.pitch = pitch
    }
}

public enum CameraFlightRouteStyle: Sendable, Equatable {
    case automatic
    case mercatorShortestPath
    case greatCircle
}

public enum CameraFlightAltitudeStyle: Sendable, Equatable {
    case direct
    case overviewFirst
}

public struct CameraFlightOptions: Sendable, Equatable {
    public static let `default` = CameraFlightOptions(duration: 1.35,
                                                      routeStyle: .automatic,
                                                      altitudeStyle: .direct)
    private static let defaultDuration: TimeInterval = 1.35

    public let duration: TimeInterval
    public let routeStyle: CameraFlightRouteStyle
    public let altitudeStyle: CameraFlightAltitudeStyle

    public init(duration: TimeInterval,
                routeStyle: CameraFlightRouteStyle = .automatic,
                altitudeStyle: CameraFlightAltitudeStyle = .direct) {
        let fallbackDuration = Self.defaultDuration
        let sanitizedDuration = duration.isFinite ? duration : fallbackDuration
        self.duration = max(0, sanitizedDuration)
        self.routeStyle = routeStyle
        self.altitudeStyle = altitudeStyle
    }
}

public final class MapCameraController {
    private weak var mapView: ImmersiveMapUIView?
    public var onMapBackgroundTap: (() -> Void)?
    public var onUserInteractionBegan: (() -> Void)?
    public var onCameraPositionChanged: ((ImmersiveMapCameraPosition) -> Void)?

    public init() {}

    public func jump(to position: ImmersiveMapCameraPosition) {
        performOnMain {
            self.mapView?.setCameraPosition(position)
        }
    }

    public func fly(to position: ImmersiveMapCameraPosition,
                    options: CameraFlightOptions = .default,
                    completion: ((Bool) -> Void)? = nil) {
        performOnMain {
            guard let mapView = self.mapView else {
                completion?(false)
                return
            }

            mapView.fly(to: position,
                        options: options,
                        completion: completion)
        }
    }

    public func cancelFlight() {
        performOnMain {
            self.mapView?.cancelFlight()
        }
    }

    public func currentCameraPosition() -> ImmersiveMapCameraPosition? {
        mapView?.currentCameraPosition()
    }

    public func anchorCamera(toAvatarMarkerWithID markerID: UInt64) {
        performOnMain {
            self.mapView?.anchorCamera(toAvatarMarkerWithID: markerID)
        }
    }

    public func anchorCamera(toAvatarMarkerWithID markerID: UInt64,
                             verticalScreenOffsetFraction: CGFloat) {
        performOnMain {
            self.mapView?.anchorCamera(toAvatarMarkerWithID: markerID,
                                       verticalScreenOffsetFraction: verticalScreenOffsetFraction)
        }
    }

    public func stopAnchoringCamera() {
        performOnMain {
            self.mapView?.stopAnchoringCamera()
        }
    }

    func attach(mapView: ImmersiveMapUIView?) {
        if Thread.isMainThread {
            self.mapView?.attach(cameraController: nil)
            self.mapView = mapView
            mapView?.attach(cameraController: self)
        } else {
            DispatchQueue.main.async {
                self.mapView?.attach(cameraController: nil)
                self.mapView = mapView
                mapView?.attach(cameraController: self)
            }
        }
    }

    func notifyMapBackgroundTap() {
        onMapBackgroundTap?()
    }

    func notifyUserInteractionBegan() {
        onUserInteractionBegan?()
    }

    func notifyCameraPositionChanged(_ position: ImmersiveMapCameraPosition) {
        onCameraPositionChanged?(position)
    }

    private func performOnMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
