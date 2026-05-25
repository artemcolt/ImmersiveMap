//
//  InFlightFramePool.swift
//  ImmersiveMapFramework
//

import Foundation

final class InFlightFramePool {
    private let slotsCount: Int
    private var occupiedSlots: [Bool]
    private let lock = NSLock()

    init(slotsCount: Int) {
        precondition(slotsCount > 0, "InFlightFramePool requires at least one slot.")
        self.slotsCount = slotsCount
        self.occupiedSlots = Array(repeating: false, count: slotsCount)
    }

    func tryAcquire() -> Int? {
        lock.lock()
        defer { lock.unlock() }

        for index in 0..<slotsCount where occupiedSlots[index] == false {
            occupiedSlots[index] = true
            return index
        }
        return nil
    }

    func release(slot index: Int) {
        lock.lock()
        defer { lock.unlock() }

        precondition(index >= 0 && index < slotsCount, "Slot index is out of bounds.")
        precondition(occupiedSlots[index], "Attempted to release a free in-flight slot.")
        occupiedSlots[index] = false
    }
}
