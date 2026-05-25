//
//  GlobePanInertiaController.swift
//  ImmersiveMapFramework
//

import CoreGraphics
import Foundation
import simd

enum GlobePanInertiaMath {
    static let maximumDeltaTime: CFTimeInterval = 0.05

    static func speed(of velocity: CGPoint) -> Double {
        hypot(Double(velocity.x), Double(velocity.y))
    }

    static func shouldStart(with velocity: CGPoint,
                            activationVelocity: Double) -> Bool {
        speed(of: velocity) >= max(0, activationVelocity)
    }

    static func shouldStop(with velocity: CGPoint,
                           stopVelocity: Double) -> Bool {
        speed(of: velocity) <= max(0, stopVelocity)
    }

    static func clampedInitialVelocity(_ velocity: CGPoint,
                                       maximumVelocity: Double) -> CGPoint {
        let limit = max(0, maximumVelocity)
        let speed = speed(of: velocity)
        guard speed.isFinite, speed > 0, speed > limit, limit > 0 else {
            return velocity
        }

        let scale = limit / speed
        return CGPoint(x: velocity.x * scale, y: velocity.y * scale)
    }

    static func clampedDeltaTime(_ deltaTime: CFTimeInterval) -> CFTimeInterval {
        guard deltaTime.isFinite else {
            return 0
        }

        return min(max(0, deltaTime), maximumDeltaTime)
    }

    static func decayedVelocity(_ velocity: CGPoint,
                                deltaTime: CFTimeInterval,
                                halfLife: Double) -> CGPoint {
        let sanitizedHalfLife = max(0.001, halfLife.isFinite ? halfLife : 0.001)
        let factor = exp(-log(2.0) * deltaTime / sanitizedHalfLife)
        return CGPoint(x: velocity.x * factor, y: velocity.y * factor)
    }
}

final class GlobePanInertiaController {
    struct Configuration {
        let isEnabled: Bool
        let halfLife: Double
        let activationVelocity: Double
        let stopVelocity: Double
        let maximumInitialVelocity: Double

        init(isEnabled: Bool,
             halfLife: Double,
             activationVelocity: Double,
             stopVelocity: Double,
             maximumInitialVelocity: Double) {
            self.isEnabled = isEnabled
            self.halfLife = max(0.001, halfLife.isFinite ? halfLife : 0.28)
            self.activationVelocity = max(0, activationVelocity.isFinite ? activationVelocity : 0)
            self.stopVelocity = max(0, stopVelocity.isFinite ? stopVelocity : 0)
            self.maximumInitialVelocity = max(0, maximumInitialVelocity.isFinite ? maximumInitialVelocity : 0)
        }
    }

    private var configuration: Configuration
    private(set) var isActive: Bool = false
    private var velocity: CGPoint = .zero
    private var lastTickTime: CFTimeInterval?

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
        if configuration.isEnabled == false {
            cancel()
        }
    }

    @discardableResult
    func start(initialVelocity: CGPoint,
               currentTime: CFTimeInterval) -> Bool {
        guard configuration.isEnabled,
              GlobePanInertiaMath.shouldStart(with: initialVelocity,
                                             activationVelocity: configuration.activationVelocity) else {
            cancel()
            return false
        }

        velocity = GlobePanInertiaMath.clampedInitialVelocity(initialVelocity,
                                                              maximumVelocity: configuration.maximumInitialVelocity)
        lastTickTime = currentTime
        isActive = true
        return true
    }

    func advance(currentTime: CFTimeInterval) -> CGPoint {
        guard isActive else {
            return .zero
        }

        guard let lastTickTime else {
            self.lastTickTime = currentTime
            return .zero
        }

        let deltaTime = GlobePanInertiaMath.clampedDeltaTime(currentTime - lastTickTime)
        self.lastTickTime = currentTime
        guard deltaTime > 0 else {
            return .zero
        }

        let translation = CGPoint(x: velocity.x * deltaTime,
                                  y: velocity.y * deltaTime)
        velocity = GlobePanInertiaMath.decayedVelocity(velocity,
                                                       deltaTime: deltaTime,
                                                       halfLife: configuration.halfLife)
        if GlobePanInertiaMath.shouldStop(with: velocity,
                                          stopVelocity: configuration.stopVelocity) {
            cancel()
        }

        return translation
    }

    func cancel() {
        isActive = false
        velocity = .zero
        lastTickTime = nil
    }
}

enum CameraFlightMath {
    static let minimumDuration: TimeInterval = 0.001
    private static let deltaEpsilon = 1e-9
    private static let greatCircleAngleEpsilon = 1e-6

    static func easeInOutCubic(_ progress: Double) -> Double {
        let clampedProgress = min(max(progress, 0), 1)
        if clampedProgress < 0.5 {
            return 4 * clampedProgress * clampedProgress * clampedProgress
        }

        let invertedProgress = -2 * clampedProgress + 2
        return 1 - (invertedProgress * invertedProgress * invertedProgress) / 2
    }

    static func shortestWrappedWorldDelta(from start: Double,
                                          to end: Double) -> Double {
        var delta = end - start
        if delta > 0.5 {
            delta -= 1.0
        } else if delta < -0.5 {
            delta += 1.0
        }
        return delta
    }

    static func interpolateWrappedWorldX(from start: Double,
                                         to end: Double,
                                         progress: Double) -> Double {
        MapProjection.wrapNormalizedWorldX(start + shortestWrappedWorldDelta(from: start, to: end) * progress)
    }

    static func shortestBearingDelta(from start: Float,
                                     to end: Float) -> Float {
        let normalizedStart = CameraBearingConstraintResolver.normalized(start)
        let normalizedEnd = CameraBearingConstraintResolver.normalized(end)
        var delta = normalizedEnd - normalizedStart
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta < -.pi {
            delta += 2 * .pi
        }
        return delta
    }

    static func interpolateBearing(from start: Float,
                                   to end: Float,
                                   progress: Double) -> Float {
        let normalizedStart = CameraBearingConstraintResolver.normalized(start)
        let delta = shortestBearingDelta(from: start, to: end)
        return CameraBearingConstraintResolver.normalized(normalizedStart + delta * Float(progress))
    }

    static func hasMeaningfulDelta(from start: MapCameraState,
                                   to end: MapCameraState) -> Bool {
        abs(shortestWrappedWorldDelta(from: start.centerWorldMercator.x, to: end.centerWorldMercator.x)) > deltaEpsilon
            || abs(end.centerWorldMercator.y - start.centerWorldMercator.y) > deltaEpsilon
            || abs(end.zoom - start.zoom) > deltaEpsilon
            || abs(shortestBearingDelta(from: start.bearing, to: end.bearing)) > Float(deltaEpsilon)
            || abs(end.pitch - start.pitch) > Float(deltaEpsilon)
    }

    static func mercatorCenter(from start: SIMD2<Double>,
                               to end: SIMD2<Double>,
                               progress: Double) -> SIMD2<Double> {
        SIMD2<Double>(interpolateWrappedWorldX(from: start.x, to: end.x, progress: progress),
                      start.y + (end.y - start.y) * progress)
    }

    static func interpolatedZoom(from startState: MapCameraState,
                                 to targetState: MapCameraState,
                                 rawProgress: Double,
                                 easedProgress: Double,
                                 altitudeStyle: CameraFlightAltitudeStyle) -> Double {
        switch altitudeStyle {
        case .direct:
            return startState.zoom + (targetState.zoom - startState.zoom) * easedProgress
        case .overviewFirst:
            let clampedProgress = min(max(rawProgress, 0), 1)
            let delayedZoomProgress = clampedProgress
                * clampedProgress
                * clampedProgress
                * clampedProgress
                * clampedProgress
                * clampedProgress
            return startState.zoom + (targetState.zoom - startState.zoom) * delayedZoomProgress
        }
    }

    static func greatCircleCenter(from start: SIMD2<Double>,
                                  to end: SIMD2<Double>,
                                  progress: Double) -> SIMD2<Double>? {
        let startLatitude = MapProjection.latitude(fromNormalizedWorldY: start.y)
        let startLongitude = MapProjection.longitude(fromNormalizedWorldX: start.x)
        let endLatitude = MapProjection.latitude(fromNormalizedWorldY: end.y)
        let endLongitude = MapProjection.longitude(fromNormalizedWorldX: end.x)

        let startVector = normalizedCartesian(latitudeRadians: startLatitude,
                                              longitudeRadians: startLongitude)
        let endVector = normalizedCartesian(latitudeRadians: endLatitude,
                                            longitudeRadians: endLongitude)

        let dotProduct = min(1.0, max(-1.0, simd_dot(startVector, endVector)))
        let angle = acos(dotProduct)
        let interpolatedVector: SIMD3<Double>
        if angle < greatCircleAngleEpsilon {
            interpolatedVector = simd_normalize(startVector + (endVector - startVector) * progress)
        } else if abs(.pi - angle) < greatCircleAngleEpsilon {
            return nil
        } else {
            let sinAngle = sin(angle)
            guard abs(sinAngle) >= greatCircleAngleEpsilon else {
                return nil
            }

            let startWeight = sin((1 - progress) * angle) / sinAngle
            let endWeight = sin(progress * angle) / sinAngle
            interpolatedVector = simd_normalize(startVector * startWeight + endVector * endWeight)
        }

        let latitude = asin(max(-1.0, min(1.0, interpolatedVector.z)))
        let longitude = atan2(interpolatedVector.y, interpolatedVector.x)
        return MapProjection.worldMercator(latitude: latitude,
                                           longitude: longitude)
    }

    private static func normalizedCartesian(latitudeRadians latitude: Double,
                                            longitudeRadians longitude: Double) -> SIMD3<Double> {
        let cosLatitude = cos(latitude)
        return simd_normalize(
            SIMD3<Double>(cosLatitude * cos(longitude),
                          cosLatitude * sin(longitude),
                          sin(latitude))
        )
    }
}

final class CameraFlightController {
    enum ResolvedRouteStyle {
        case mercatorShortestPath
        case greatCircle
    }

    struct Step {
        let cameraState: MapCameraState
        let didFinish: Bool
    }

    private struct Flight {
        let startState: MapCameraState
        let targetState: MapCameraState
        let duration: TimeInterval
        let routeStyle: ResolvedRouteStyle
        let altitudeStyle: CameraFlightAltitudeStyle
        let startTime: CFTimeInterval
    }

    private var flight: Flight?

    var isActive: Bool {
        flight != nil
    }

    @discardableResult
    func start(from startState: MapCameraState,
               to targetState: MapCameraState,
               duration: TimeInterval,
               routeStyle: ResolvedRouteStyle,
               altitudeStyle: CameraFlightAltitudeStyle,
               currentTime: CFTimeInterval) -> Bool {
        let sanitizedDuration = max(CameraFlightMath.minimumDuration, duration.isFinite ? duration : 0)
        guard CameraFlightMath.hasMeaningfulDelta(from: startState, to: targetState) else {
            cancel()
            return false
        }

        flight = Flight(startState: startState,
                        targetState: targetState,
                        duration: sanitizedDuration,
                        routeStyle: routeStyle,
                        altitudeStyle: altitudeStyle,
                        startTime: currentTime)
        return true
    }

    func advance(currentTime: CFTimeInterval) -> Step? {
        guard let flight else {
            return nil
        }

        let rawProgress = flight.duration > 0 ? (currentTime - flight.startTime) / flight.duration : 1
        let clampedProgress = min(max(rawProgress, 0), 1)
        let easedProgress = CameraFlightMath.easeInOutCubic(clampedProgress)
        let centerWorldMercator: SIMD2<Double>
        switch flight.routeStyle {
        case .mercatorShortestPath:
            centerWorldMercator = CameraFlightMath.mercatorCenter(from: flight.startState.centerWorldMercator,
                                                                  to: flight.targetState.centerWorldMercator,
                                                                  progress: easedProgress)
        case .greatCircle:
            centerWorldMercator = CameraFlightMath.greatCircleCenter(from: flight.startState.centerWorldMercator,
                                                                     to: flight.targetState.centerWorldMercator,
                                                                     progress: easedProgress)
            ?? CameraFlightMath.mercatorCenter(from: flight.startState.centerWorldMercator,
                                               to: flight.targetState.centerWorldMercator,
                                               progress: easedProgress)
        }

        let zoom = CameraFlightMath.interpolatedZoom(from: flight.startState,
                                                     to: flight.targetState,
                                                     rawProgress: clampedProgress,
                                                     easedProgress: easedProgress,
                                                     altitudeStyle: flight.altitudeStyle)
        let bearing = CameraFlightMath.interpolateBearing(from: flight.startState.bearing,
                                                          to: flight.targetState.bearing,
                                                          progress: easedProgress)
        let pitch = flight.startState.pitch + (flight.targetState.pitch - flight.startState.pitch) * Float(easedProgress)
        let nextState = MapCameraState(centerWorldMercator: centerWorldMercator,
                                       zoom: zoom,
                                       bearing: bearing,
                                       pitch: pitch)
        let didFinish = clampedProgress >= 1
        if didFinish {
            self.flight = nil
        }

        return Step(cameraState: nextState,
                    didFinish: didFinish)
    }

    func cancel() {
        flight = nil
    }
}
