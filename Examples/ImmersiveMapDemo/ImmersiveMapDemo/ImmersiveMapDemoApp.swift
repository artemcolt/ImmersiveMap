import SwiftUI
import UIKit
import ImmersiveMap

@main
struct ImmersiveMapDemoApp: App {
    var body: some Scene {
        WindowGroup {
            DemoMapScreen()
        }
    }
}

struct DemoMapScreen: View {
    @State private var camera = MapCameraController()
    @State private var avatars = AvatarsController()
    @State private var mode: DemoMode = .city

    var body: some View {
        ZStack(alignment: .topLeading) {
            ImmersiveMapView(
                settings: mapSettings,
                avatarsController: avatars,
                cameraPosition: mode.cameraPosition,
                cameraController: camera,
                visibilityPolicy: mode.visibilityPolicy
            )
            .ignoresSafeArea()

            modeBadge
                .padding(.top, 18)
                .padding(.leading, 18)
        }
        .task {
            await seedDemoMarkers()
            await cycleCameraForScreenshots()
        }
    }

    private var mapSettings: MapSettings {
        var settings = MapSettings.default
        let environment = ProcessInfo.processInfo.environment
        let tileBaseURLString = environment["IMMERSIVE_MAP_TILE_BASE_URL"] ?? "https://tucik.moscow/api/v1/map/tiles"
        settings.tiles.network.tileBaseURL = URL(string: tileBaseURLString)!
        settings.tiles.network.authorizationToken = environment["IMMERSIVE_MAP_AUTH_TOKEN"]
        settings.renderLoop.forceContinuousRendering = false
        settings.debug.overlayEnabled = false
        settings.debug.tileOverlayEnabled = false
        return settings
    }

    private var modeBadge: some View {
        Text(mode.title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @MainActor
    private func seedDemoMarkers() async {
        avatars.set([
            AvatarMarker(
                id: 1,
                coordinate: GeoCoordinate(latitude: 55.7558, longitude: 37.6173),
                image: Self.markerImage(fill: UIColor(red: 0.16, green: 0.64, blue: 0.98, alpha: 1)),
                batteryBadge: AvatarBatteryBadge(levelPct: 82),
                speedBadge: AvatarSpeedBadge(kilometersPerHour: 5),
                isSelected: true
            ),
            AvatarMarker(
                id: 2,
                coordinate: GeoCoordinate(latitude: 55.7512, longitude: 37.6297),
                image: Self.markerImage(fill: UIColor(red: 0.96, green: 0.35, blue: 0.31, alpha: 1)),
                batteryBadge: AvatarBatteryBadge(levelPct: 54),
                speedBadge: AvatarSpeedBadge(kilometersPerHour: 18)
            )
        ])
    }

    @MainActor
    private func cycleCameraForScreenshots() async {
        try? await Task.sleep(for: .seconds(5))
        mode = .globe
        camera.fly(to: DemoMode.globe.cameraPosition, options: CameraFlightOptions(duration: 1.2))

        try? await Task.sleep(for: .seconds(5))
        mode = .city
        camera.fly(to: DemoMode.city.cameraPosition, options: CameraFlightOptions(duration: 1.0))
    }

    private static func markerImage(fill: UIColor) -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10)
            fill.setFill()
            context.cgContext.fillEllipse(in: rect)
            UIColor.white.withAlphaComponent(0.92).setStroke()
            context.cgContext.setLineWidth(8)
            context.cgContext.strokeEllipse(in: rect)
        }
    }
}

private enum DemoMode {
    case city
    case globe

    var title: String {
        switch self {
        case .city:
            return "ImmersiveMap city view"
        case .globe:
            return "ImmersiveMap globe view"
        }
    }

    var visibilityPolicy: VisibilityPolicy {
        switch self {
        case .city:
            return .preferFlat
        case .globe:
            return .preferGlobe
        }
    }

    var cameraPosition: ImmersiveMapCameraPosition {
        switch self {
        case .city:
            return ImmersiveMapCameraPosition(
                latitudeDegrees: 55.7558,
                longitudeDegrees: 37.6173,
                zoom: 13.2,
                bearing: .pi / 10,
                pitch: .pi / 5
            )
        case .globe:
            return ImmersiveMapCameraPosition(
                latitudeDegrees: 52.0,
                longitudeDegrees: 38.0,
                zoom: 1.35,
                bearing: 0,
                pitch: 0
            )
        }
    }
}
