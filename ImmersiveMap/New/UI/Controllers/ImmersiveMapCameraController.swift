// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import CoreGraphics
import Foundation

enum ImmersiveMapCameraCommand {
    case jump(ImmersiveMapCameraPosition)
    case fly(ImmersiveMapCameraPosition, CameraFlightOptions, ((Bool) -> Void)?)
    case cancelFlight
    case anchorAvatarMarker(UInt64, CGFloat)
    case stopAnchoring
}

public final class ImmersiveMapCameraController {
    private let lock = NSLock()
    private var currentPosition: ImmersiveMapCameraPosition?
    private var pendingCommands: [ImmersiveMapCameraCommand] = []
    private var commandHandler: ((ImmersiveMapCameraCommand) -> Void)?

    public var onMapBackgroundTap: (() -> Void)?
    public var onUserInteractionBegan: (() -> Void)?
    public var onCameraPositionChanged: ((ImmersiveMapCameraPosition) -> Void)?

    public init() {}

    public func jump(to position: ImmersiveMapCameraPosition) {
        updateCurrentCameraPosition(position)
        enqueue(.jump(position))
    }

    public func fly(to position: ImmersiveMapCameraPosition,
                    options: CameraFlightOptions = .default,
                    completion: ((Bool) -> Void)? = nil) {
        enqueue(.fly(position, options, completion))
    }

    public func cancelFlight() {
        enqueue(.cancelFlight)
    }

    public func currentCameraPosition() -> ImmersiveMapCameraPosition? {
        lock.lock()
        defer { lock.unlock() }
        return currentPosition
    }

    public func anchorCamera(toAvatarMarkerWithID markerID: UInt64) {
        enqueue(.anchorAvatarMarker(markerID, 0))
    }

    public func anchorCamera(toAvatarMarkerWithID markerID: UInt64,
                             verticalScreenOffsetFraction: CGFloat) {
        enqueue(.anchorAvatarMarker(markerID, verticalScreenOffsetFraction))
    }

    public func stopAnchoringCamera() {
        enqueue(.stopAnchoring)
    }

    func setCommandHandler(_ handler: ((ImmersiveMapCameraCommand) -> Void)?) {
        performOnMain {
            self.commandHandler = handler
            guard let handler else {
                return
            }

            let commands = self.pendingCommands
            self.pendingCommands.removeAll(keepingCapacity: true)
            commands.forEach(handler)
        }
    }

    func updateCurrentCameraPosition(_ position: ImmersiveMapCameraPosition?) {
        lock.lock()
        currentPosition = position
        lock.unlock()
    }

    private func enqueue(_ command: ImmersiveMapCameraCommand) {
        performOnMain {
            guard let commandHandler = self.commandHandler else {
                self.pendingCommands.append(command)
                return
            }

            commandHandler(command)
        }
    }

    func notifyMapBackgroundTap() {
        onMapBackgroundTap?()
    }

    func notifyUserInteractionBegan() {
        onUserInteractionBegan?()
    }

    func notifyCameraPositionChanged(_ position: ImmersiveMapCameraPosition) {
        updateCurrentCameraPosition(position)
        onCameraPositionChanged?(position)
    }
}
