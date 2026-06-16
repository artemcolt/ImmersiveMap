// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

//
//  BaseLabelPresentationStateStore.swift
//  ImmersiveMap
//

import Foundation

struct BaseLabelPresentationResolution {
    let fadeAlphas: [Float]
    let hasActiveAnimations: Bool
}

struct BaseLabelPresentationInput {
    static let empty = BaseLabelPresentationInput(labelKey: 0,
                                                  duplicate: 0,
                                                  isRetained: 0,
                                                  isValid: false)

    let labelKey: UInt64
    let duplicate: UInt8
    let isRetained: UInt8
    let isValid: Bool
}

final class BaseLabelPresentationStateStore {
    private struct Entry {
        var currentAlpha: Float
        var targetAlpha: Float
        var lastUpdateTime: TimeInterval
        var lastSeenFrameIndex: UInt64
    }

    private var entries: [UInt64: Entry] = [:]

    func resolveAlphas(inputs: [BaseLabelPresentationInput],
                       collisionFlags: [UInt32],
                       time: TimeInterval,
                       frameIndex: UInt64,
                       fadeInSeconds: TimeInterval,
                       fadeOutSeconds: TimeInterval) -> BaseLabelPresentationResolution {
        let targetVisibility = inputs.indices.map { index in
            let input = inputs[index]
            let collisionHidden = index < collisionFlags.count ? (collisionFlags[index] != 0) : false
            return input.isValid && input.duplicate == 0 && input.isRetained == 0 && collisionHidden == false
        }
        return resolveAlphas(inputs: inputs,
                             targetVisibility: targetVisibility,
                             time: time,
                             frameIndex: frameIndex,
                             fadeInSeconds: fadeInSeconds,
                             fadeOutSeconds: fadeOutSeconds)
    }

    func resolveAlphas(inputs: [BaseLabelPresentationInput],
                       targetVisibility: [Bool],
                       time: TimeInterval,
                       frameIndex: UInt64,
                       fadeInSeconds: TimeInterval,
                       fadeOutSeconds: TimeInterval) -> BaseLabelPresentationResolution {
        var resolved = Array(repeating: Float(0), count: inputs.count)
        var hasActiveAnimations = false

        for index in inputs.indices {
            let input = inputs[index]
            guard input.isValid else {
                continue
            }

            if input.duplicate != 0 {
                resolved[index] = 0
                continue
            }

            let isVisibleTarget = index < targetVisibility.count ? targetVisibility[index] : false
            let targetAlpha: Float = isVisibleTarget ? 1 : 0
            let alphaResolution = resolveAlpha(labelKey: input.labelKey,
                                               targetAlpha: targetAlpha,
                                               time: time,
                                               frameIndex: frameIndex,
                                               fadeInSeconds: fadeInSeconds,
                                               fadeOutSeconds: fadeOutSeconds)
            resolved[index] = alphaResolution.alpha
            hasActiveAnimations = hasActiveAnimations || alphaResolution.isActive
        }

        hasActiveAnimations = fadeOutMissingEntries(currentTime: time,
                                                    frameIndex: frameIndex,
                                                    fadeInSeconds: fadeInSeconds,
                                                    fadeOutSeconds: fadeOutSeconds) || hasActiveAnimations
        return BaseLabelPresentationResolution(fadeAlphas: resolved,
                                               hasActiveAnimations: hasActiveAnimations)
    }

    func currentAlphas(inputs: [BaseLabelPresentationInput],
                       time: TimeInterval,
                       fadeInSeconds: TimeInterval,
                       fadeOutSeconds: TimeInterval) -> [Float] {
        inputs.map { input in
            guard input.isValid,
                  input.duplicate == 0,
                  let entry = entries[input.labelKey] else {
                return 0
            }

            var advanced = entry
            advance(&advanced,
                    to: advanced.targetAlpha,
                    currentTime: time,
                    fadeInSeconds: fadeInSeconds,
                    fadeOutSeconds: fadeOutSeconds)
            return advanced.currentAlpha
        }
    }

    func reset() {
        entries.removeAll(keepingCapacity: false)
    }

    private func resolveAlpha(labelKey: UInt64,
                              targetAlpha: Float,
                              time: TimeInterval,
                              frameIndex: UInt64,
                              fadeInSeconds: TimeInterval,
                              fadeOutSeconds: TimeInterval) -> (alpha: Float, isActive: Bool) {
        var entry = entries[labelKey] ?? Entry(currentAlpha: 0,
                                               targetAlpha: 0,
                                               lastUpdateTime: time,
                                               lastSeenFrameIndex: frameIndex)
        advance(&entry,
                to: entry.targetAlpha,
                currentTime: time,
                fadeInSeconds: fadeInSeconds,
                fadeOutSeconds: fadeOutSeconds)
        entry.targetAlpha = targetAlpha
        entry.lastSeenFrameIndex = frameIndex
        entry.lastUpdateTime = time
        entries[labelKey] = entry
        return (entry.currentAlpha, isActive: isActive(entry))
    }

    private func fadeOutMissingEntries(currentTime: TimeInterval,
                                       frameIndex: UInt64,
                                       fadeInSeconds: TimeInterval,
                                       fadeOutSeconds: TimeInterval) -> Bool {
        guard entries.isEmpty == false else {
            return false
        }

        let staleKeys = entries.compactMap { key, entry in
            entry.lastSeenFrameIndex == frameIndex ? nil : key
        }
        var hasActiveAnimations = false

        for key in staleKeys {
            guard var entry = entries[key] else {
                continue
            }

            advance(&entry,
                    to: entry.targetAlpha,
                    currentTime: currentTime,
                    fadeInSeconds: fadeInSeconds,
                    fadeOutSeconds: fadeOutSeconds)
            entry.targetAlpha = 0
            entry.lastUpdateTime = currentTime
            hasActiveAnimations = hasActiveAnimations || isActive(entry)

            if entry.currentAlpha <= 0.0001 {
                entries.removeValue(forKey: key)
            } else {
                entries[key] = entry
            }
        }

        return hasActiveAnimations
    }

    private func advance(_ entry: inout Entry,
                         to targetAlpha: Float,
                         currentTime: TimeInterval,
                         fadeInSeconds: TimeInterval,
                         fadeOutSeconds: TimeInterval) {
        let elapsed = max(0, currentTime - entry.lastUpdateTime)
        guard elapsed > 0 else {
            return
        }

        if targetAlpha > entry.currentAlpha {
            let duration = max(0, fadeInSeconds)
            if duration == 0 {
                entry.currentAlpha = targetAlpha
            } else {
                let step = Float(elapsed / duration)
                entry.currentAlpha = min(targetAlpha, entry.currentAlpha + step)
            }
        } else if targetAlpha < entry.currentAlpha {
            let duration = max(0, fadeOutSeconds)
            if duration == 0 {
                entry.currentAlpha = targetAlpha
            } else {
                let step = Float(elapsed / duration)
                entry.currentAlpha = max(targetAlpha, entry.currentAlpha - step)
            }
        }
    }

    private func isActive(_ entry: Entry) -> Bool {
        abs(entry.currentAlpha - entry.targetAlpha) > 0.001
    }
}
