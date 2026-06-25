// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

struct LRUMemoryCache<Key: Hashable, Value> {
    struct Entry {
        let key: Key
        let value: Value
        let cost: Int
    }

    private let costLimit: Int
    private var entriesByKey: [Key: Entry] = [:]
    private var keysByUsage: [Key] = []

    private(set) var totalCost = 0

    var count: Int {
        entriesByKey.count
    }

    init(costLimit: Int) {
        self.costLimit = max(0, costLimit)
    }

    func cost(forKey key: Key) -> Int? {
        entriesByKey[key]?.cost
    }

    mutating func value(forKey key: Key) -> Value? {
        guard let entry = entriesByKey[key] else {
            return nil
        }

        markRecentlyUsed(key)
        return entry.value
    }

    mutating func setValue(_ value: Value, forKey key: Key, cost: Int) -> [Entry]? {
        let normalizedCost = max(0, cost)
        if let existingEntry = entriesByKey[key] {
            totalCost -= existingEntry.cost
            removeUsageKey(key)
        }

        let entry = Entry(key: key, value: value, cost: normalizedCost)
        entriesByKey[key] = entry
        keysByUsage.append(key)
        totalCost += normalizedCost

        let evictedEntries = evictIfNeeded(protectedKey: key)
        return evictedEntries.isEmpty ? nil : evictedEntries
    }

    mutating func removeAll() -> [Entry] {
        let removedEntries = keysByUsage.compactMap { entriesByKey[$0] }
        entriesByKey.removeAll(keepingCapacity: false)
        keysByUsage.removeAll(keepingCapacity: false)
        totalCost = 0
        return removedEntries
    }

    private mutating func evictIfNeeded(protectedKey: Key) -> [Entry] {
        var evictedEntries: [Entry] = []
        while totalCost > costLimit, entriesByKey.count > 1 {
            guard let key = keysByUsage.first else {
                break
            }

            if key == protectedKey {
                keysByUsage.removeFirst()
                keysByUsage.append(key)
                continue
            }

            keysByUsage.removeFirst()
            guard let entry = entriesByKey.removeValue(forKey: key) else {
                continue
            }
            totalCost -= entry.cost
            evictedEntries.append(entry)
        }
        return evictedEntries
    }

    private mutating func markRecentlyUsed(_ key: Key) {
        removeUsageKey(key)
        keysByUsage.append(key)
    }

    private mutating func removeUsageKey(_ key: Key) {
        guard let index = keysByUsage.firstIndex(of: key) else {
            return
        }
        keysByUsage.remove(at: index)
    }
}
