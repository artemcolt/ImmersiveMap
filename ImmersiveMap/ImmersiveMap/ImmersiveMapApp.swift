//
//  ImmersiveMapApp.swift
//  ImmersiveMap
//
//  Created by Artem on 8/31/25.
//

import SwiftUI
import ImmersiveMapFramework

@main
struct ImmersiveMapApp: App {
    var body: some Scene {
        WindowGroup {
            ImmersiveMapView().ignoresSafeArea(edges: .all)
        }
    }
}
