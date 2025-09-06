//
//  ImmersiveMapView.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import SwiftUI
import UIKit // Для UIView

public struct ImmersiveMapView: UIViewRepresentable {
    public init() {
        
    }
    
    public func makeUIView(context: Context) -> ImmersiveMapUIView {
        return ImmersiveMapUIView()
    }
    
    public func updateUIView(_ uiView: ImmersiveMapUIView, context: Context) {
        
    }
}
