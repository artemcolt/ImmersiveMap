//
//  TileMvtParser+ParseGeometryStyleData.swift
//  ImmersiveMapFramework
//  Created by Artem on 1/21/26.
//

import Foundation

extension TileMvtParser {
    struct ParseGeometryStyleData {
        let lineWidth: Double
        let lineCapRound: Bool
        let lineJoinRound: Bool
        let dashLength: Double
        let dashGap: Double
        let dashResetsPerSegment: Bool

        var usesDashPattern: Bool {
            dashLength > 0 && dashGap > 0
        }
        
        init(lineWidth: Double,
             lineCapRound: Bool = false,
             lineJoinRound: Bool = false,
             dashLength: Double = 0,
             dashGap: Double = 0,
             dashResetsPerSegment: Bool = false) {
            self.lineWidth = lineWidth
            self.lineCapRound = lineCapRound
            self.lineJoinRound = lineJoinRound
            self.dashLength = dashLength
            self.dashGap = dashGap
            self.dashResetsPerSegment = dashResetsPerSegment
        }
    }
}
