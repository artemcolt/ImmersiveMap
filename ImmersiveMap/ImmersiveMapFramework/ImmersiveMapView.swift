//
//  ImmersiveMapView.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import SwiftUI
import UIKit // Для UIView

public struct ImmersiveMapView: UIViewRepresentable {
    private let config: MapConfiguration

    public init(config: MapConfiguration = .default) {
        self.config = config
    }
    
    public func makeUIView(context: Context) -> ImmersiveMapUIView {
        return ImmersiveMapUIView(frame: .zero, config: config)
    }
    
    public func updateUIView(_ uiView: ImmersiveMapUIView, context: Context) {
        if config.debugRenderLogging {
            print("update UI view")
        }
    }
}
