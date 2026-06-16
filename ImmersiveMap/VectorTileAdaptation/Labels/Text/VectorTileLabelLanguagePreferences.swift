// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct VectorTileLabelLanguagePreferences: Equatable {
    struct Candidate: Equatable {
        enum Kind: Equatable {
            case preferred
            case native
            case english
        }

        let fieldName: String
        let kind: Kind
    }

    let fallbackChain: [Candidate]
    let selectedLanguage: ImmersiveMapSettings.LabelLanguage

    static func from(settingsLanguage: ImmersiveMapSettings.LabelLanguage) -> VectorTileLabelLanguagePreferences {
        let preferredFieldName = "name_\(settingsLanguage.providerFieldSuffix)"
        var fallbackChain: [Candidate] = []

        if settingsLanguage == .english {
            fallbackChain.append(Candidate(fieldName: "name_en", kind: .english))
            fallbackChain.append(Candidate(fieldName: "name", kind: .native))
        } else {
            fallbackChain.append(Candidate(fieldName: preferredFieldName, kind: .preferred))
            fallbackChain.append(Candidate(fieldName: "name", kind: .native))
            fallbackChain.append(Candidate(fieldName: "name_en", kind: .english))
        }

        return VectorTileLabelLanguagePreferences(fallbackChain: fallbackChain,
                                                  selectedLanguage: settingsLanguage)
    }
}
