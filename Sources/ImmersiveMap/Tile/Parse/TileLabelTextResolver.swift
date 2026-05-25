//
//  TileLabelTextResolver.swift
//  TucikMap
//
//  Created by Artem on 1/21/26.
//

import Foundation

final class TileLabelTextResolver {
    private let config: MapSettings

    private static let latinSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let cyrillicSet = CharacterSet(charactersIn: UnicodeScalar(0x0400)!...UnicodeScalar(0x04FF)!)
    private static let digitsSet = CharacterSet(charactersIn: "0123456789")
    private static let punctuationSet = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:'\\\",./<>?")

    init(config: MapSettings) {
        self.config = config
    }

    func resolveLabelText(attributes: [String: VectorTile_Tile.Value]) -> String? {
        let name = attributes["name"]?.stringValue
        let nameEn = attributes["name_en"]?.stringValue
        let nameRu = attributes["name_ru"]?.stringValue

        let candidates: [LabelTextCandidate]
        switch config.labels.language {
        case .russian:
            candidates = [
                LabelTextCandidate(text: nameRu, requiresSelectedLanguageMatch: false),
                LabelTextCandidate(text: name, requiresSelectedLanguageMatch: true),
                LabelTextCandidate(text: nameEn, requiresSelectedLanguageMatch: false)
            ]
        case .english:
            candidates = [
                LabelTextCandidate(text: nameEn, requiresSelectedLanguageMatch: false),
                LabelTextCandidate(text: name, requiresSelectedLanguageMatch: true),
                LabelTextCandidate(text: nameRu, requiresSelectedLanguageMatch: false)
            ]
        }

        for candidate in candidates {
            guard let text = candidate.text,
                  text.isEmpty == false,
                  isRenderable(text: text) else {
                continue
            }
            if candidate.requiresSelectedLanguageMatch,
               isNameInSelectedLanguage(text) == false {
                continue
            }
            return text
        }

        return nil
    }

    func resolveHouseNumberText(attributes: [String: VectorTile_Tile.Value]) -> String? {
        guard let text = attributes["house_num"]?.stringValue,
              text.isEmpty == false,
              isRenderable(text: text) else {
            return nil
        }
        return text
    }

    private func isNameInSelectedLanguage(_ name: String) -> Bool {
        let hasCyrillic = containsAny(from: TileLabelTextResolver.cyrillicSet, in: name)
        let hasLatin = containsAny(from: TileLabelTextResolver.latinSet, in: name)
        switch config.labels.language {
        case .english:
            return hasLatin && hasCyrillic == false
        case .russian:
            return hasCyrillic
        }
    }

    private func isRenderable(text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if TileLabelTextResolver.latinSet.contains(scalar) ||
                TileLabelTextResolver.cyrillicSet.contains(scalar) ||
                TileLabelTextResolver.digitsSet.contains(scalar) ||
                TileLabelTextResolver.punctuationSet.contains(scalar) ||
                CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            return false
        }
        return true
    }

    private func containsAny(from set: CharacterSet, in text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if set.contains(scalar) {
                return true
            }
        }
        return false
    }
}

private struct LabelTextCandidate {
    let text: String?
    let requiresSelectedLanguageMatch: Bool
}
