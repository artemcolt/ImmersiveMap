//
//  AvatarsController.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/26/26.
//

import Foundation
import CoreGraphics
import simd
#if canImport(UIKit)
import UIKit
#endif

public struct AvatarsSnapshot {
    public let markers: [AvatarMarker]
    public let removedIds: [UInt64]
    public let imageUpdateIds: [UInt64]
    public let version: UInt64
}

public final class AvatarsController {
    private let lock = NSLock()
    private var markersById: [UInt64: AvatarMarker] = [:]
    private var removedIds: Set<UInt64> = []
    private var imageUpdateIds: Set<UInt64> = []
    private var version: UInt64 = 0
    private var hasChanges: Bool = false
    private var changeHandler: (() -> Void)?

    public init() {}

    func setChangeHandler(_ handler: (() -> Void)?) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
    }

    public func add(_ marker: AvatarMarker) {
        upsert([marker])
    }

    public func add(_ markers: [AvatarMarker]) {
        upsert(markers)
    }

    public func set(_ markers: [AvatarMarker]) {
        lock.lock()
        markersById = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })
        removedIds.removeAll(keepingCapacity: true)
        imageUpdateIds = Set(markersById.keys)
        let changeHandler = markChangedLocked()
        lock.unlock()
        changeHandler?()
    }

    public func upsert(_ markers: [AvatarMarker]) {
        lock.lock()
        for marker in markers {
            markersById[marker.id] = marker
            removedIds.remove(marker.id)
            imageUpdateIds.insert(marker.id)
        }
        let changeHandler = markChangedLocked()
        lock.unlock()
        changeHandler?()
    }

    public func move(id: UInt64, to coordinate: GeoCoordinate) {
        lock.lock()
        guard var marker = markersById[id] else {
            lock.unlock()
            return
        }
        marker.coordinate = coordinate
        markersById[id] = marker
        let changeHandler = markChangedLocked()
        lock.unlock()
        changeHandler?()
    }

    public func move(id: UInt64, latitude: Double, longitude: Double) {
        move(id: id, to: GeoCoordinate(latitude: latitude, longitude: longitude))
    }

    func marker(id: UInt64) -> AvatarMarker? {
        lock.lock()
        defer { lock.unlock() }
        return markersById[id]
    }

    public func update(id: UInt64,
                       image: CGImage? = nil,
                       borderColor: SIMD4<Float>? = nil,
                       isSelected: Bool? = nil) {
        lock.lock()
        guard var marker = markersById[id] else {
            lock.unlock()
            return
        }
        if let image {
            marker.image = image
            imageUpdateIds.insert(id)
        }
        if let borderColor {
            marker.borderColor = borderColor
        }
        if let isSelected {
            marker.isSelected = isSelected
        }
        markersById[id] = marker
        let changeHandler = markChangedLocked()
        lock.unlock()
        changeHandler?()
    }

#if canImport(UIKit)
    public func update(id: UInt64,
                       image: UIImage,
                       borderColor: SIMD4<Float>? = nil,
                       isSelected: Bool? = nil) {
        guard let cgImage = image.cgImage else {
            preconditionFailure("UIImage must have CGImage backing.")
        }
        update(id: id,
               image: cgImage,
               borderColor: borderColor,
               isSelected: isSelected)
    }
#endif

    public func remove(ids: [UInt64]) {
        lock.lock()
        for id in ids {
            markersById.removeValue(forKey: id)
            removedIds.insert(id)
            imageUpdateIds.remove(id)
        }
        let changeHandler = markChangedLocked()
        lock.unlock()
        changeHandler?()
    }

    public func remove(id: UInt64) {
        remove(ids: [id])
    }

    public func clear() {
        lock.lock()
        removedIds.formUnion(markersById.keys)
        markersById.removeAll(keepingCapacity: true)
        imageUpdateIds.removeAll(keepingCapacity: true)
        let changeHandler = markChangedLocked()
        lock.unlock()
        changeHandler?()
    }

    func consumeSnapshot() -> AvatarsSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard hasChanges else { return nil }
        hasChanges = false
        let snapshot = AvatarsSnapshot(markers: Array(markersById.values),
                                       removedIds: Array(removedIds),
                                       imageUpdateIds: Array(imageUpdateIds),
                                       version: version)
        removedIds.removeAll(keepingCapacity: true)
        imageUpdateIds.removeAll(keepingCapacity: true)
        return snapshot
    }

    private func markChangedLocked() -> (() -> Void)? {
        version &+= 1
        hasChanges = true
        return changeHandler
    }
}
