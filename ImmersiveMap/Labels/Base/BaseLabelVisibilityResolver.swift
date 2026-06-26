// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

enum BaseLabelVisibilityResolver {
    static let activeAlphaThreshold: Float = 0.0001

    static func targetVisibility(inputs: [BaseLabelPresentationInput],
                                 collisionFlags: [UInt32],
                                 horizonVisibility: [Bool],
                                 collisionVisibilityIsFresh: Bool = true) -> [Bool] {
        inputs.indices.map { index in
            let input = inputs[index]
            let collisionHidden = collisionVisibilityIsFresh && index < collisionFlags.count ? collisionFlags[index] != 0 : false
            let horizonVisible = index < horizonVisibility.count ? horizonVisibility[index] : false
            return input.isValid &&
                input.duplicate == 0 &&
                input.isRetained == 0 &&
                collisionHidden == false &&
                horizonVisible
        }
    }

    static func collisionCandidates(baseCandidates: [ScreenCollisionCandidate],
                                    screenPoints: [ScreenPointOutput],
                                    horizonVisibility: [Bool],
                                    currentAlphas: [Float]) -> [ScreenCollisionCandidate] {
        var candidates = baseCandidates
        let count = min(candidates.count, screenPoints.count)

        for index in 0..<count {
            let point = screenPoints[index]
            candidates[index].position = point.position

            guard candidates[index].isEnabled,
                  point.visible != 0 else {
                candidates[index].isEnabled = false
                continue
            }

            let horizonVisible = index < horizonVisibility.count ? horizonVisibility[index] : false
            let currentAlpha = index < currentAlphas.count ? currentAlphas[index] : 0
            candidates[index].isEnabled = horizonVisible || currentAlpha > activeAlphaThreshold
        }

        if count < candidates.count {
            for index in count..<candidates.count {
                candidates[index].isEnabled = false
            }
        }

        return candidates
    }

    static func horizonReservationSignature(horizonVisibility: [Bool],
                                            currentAlphas: [Float]) -> [Int] {
        let count = min(horizonVisibility.count, currentAlphas.count)
        guard count > 0 else {
            return []
        }

        var signature: [Int] = []
        for index in 0..<count where horizonVisibility[index] == false &&
            currentAlphas[index] > activeAlphaThreshold {
            signature.append(index)
        }
        return signature
    }
}
