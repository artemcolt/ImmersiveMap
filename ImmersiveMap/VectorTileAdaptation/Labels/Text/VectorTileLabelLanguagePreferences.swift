// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

struct VectorTileLabelLanguagePreferences: Equatable {
    enum LanguageCode: Equatable {
        case russian
        case english
        case native
    }

    let fallbackChain: [LanguageCode]
    let selectedLanguage: LanguageCode

    static func from(settingsLanguage: ImmersiveMapSettings.LabelLanguage) -> VectorTileLabelLanguagePreferences {
        switch settingsLanguage {
        case .russian:
            return VectorTileLabelLanguagePreferences(fallbackChain: [.russian, .native, .english],
                                                      selectedLanguage: .russian)
        case .english:
            return VectorTileLabelLanguagePreferences(fallbackChain: [.english, .native, .russian],
                                                      selectedLanguage: .english)
        }
    }
}
