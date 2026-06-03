// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import SwiftUI
import UIKit
import ImmersiveMap

@main
struct ImmersiveMapMacApp: App {
    var body: some Scene {
        WindowGroup {
            HostMapScreen()
        }
    }
}

struct HostMapScreen: View {
    @State private var camera = ImmersiveMapCameraController()
    @State private var avatars = ImmersiveMapAvatarsController()
    @State private var mode: PreviewMode = .initial
    @State private var liveCameraPosition = PreviewMode.initial.cameraPosition

    var body: some View {
        ZStack {
            ImmersiveMapView(
                settings: mapSettings,
                avatarsController: avatars,
                cameraPosition: mode.cameraPosition,
                cameraController: camera
            )
            .ignoresSafeArea()

            modeBadge
                .padding(.top, 18)
                .padding(.leading, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            CameraControlPanel(
                cameraPosition: liveCameraPosition,
                maximumPitch: mapSettings.camera.maximumPitch
            ) { nextPosition in
                liveCameraPosition = nextPosition
                camera.jump(to: nextPosition)
            }
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .onAppear {
            camera.onCameraPositionChanged = { position in
                Task { @MainActor in
                    liveCameraPosition = position
                }
            }
        }
        .onDisappear {
            camera.onCameraPositionChanged = nil
        }
        .task {
            await seedPreviewMarkers()
            await cycleCameraForScreenshotsIfNeeded()
        }
    }

    private var mapSettings: ImmersiveMapSettings {
        var settings = ImmersiveMapSettings.default
        let environment = ProcessInfo.processInfo.environment
        if let mapboxAccessToken = environment["IMMERSIVE_MAP_MAPBOX_ACCESS_TOKEN"], mapboxAccessToken.isEmpty == false {
            let tilesetID = Self.resolvedMapboxTilesetID(environment["IMMERSIVE_MAP_MAPBOX_TILESET_ID"])
            settings.tiles.network.tileBaseURL = URL(string: "https://api.mapbox.com/v4/\(tilesetID)")!
            settings.tiles.network.authorizationToken = mapboxAccessToken
            settings.tiles.network.authorizationMode = .accessTokenQuery(parameterName: "access_token")
        } else {
            let tileBaseURLString = environment["IMMERSIVE_MAP_TILE_BASE_URL"] ?? "https://example.com/api/v1/map/tiles"
            settings.tiles.network.tileBaseURL = URL(string: tileBaseURLString)!
            settings.tiles.network.authorizationToken = environment["IMMERSIVE_MAP_AUTH_TOKEN"]
            settings.tiles.network.authorizationMode = .bearerHeader
        }
        settings.renderLoop.forceContinuousRendering = false
        settings.debug.overlayEnabled = false
        settings.debug.tileOverlayEnabled = false
        return settings
    }

    private static func resolvedMapboxTilesetID(_ configuredTilesetID: String?) -> String {
        let defaultTilesetID = "mapbox.mapbox-streets-v8,mapbox.mapbox-terrain-v2"
        let legacyDefaultTilesetID = "mapbox.mapbox-streets-v8"
        guard let configuredTilesetID, configuredTilesetID.isEmpty == false else {
            return defaultTilesetID
        }
        return configuredTilesetID == legacyDefaultTilesetID ? defaultTilesetID : configuredTilesetID
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
    private func seedPreviewMarkers() async {
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
    private func cycleCameraForScreenshotsIfNeeded() async {
        guard PreviewMode.shouldAutoCycle else {
            return
        }

        try? await Task.sleep(for: .seconds(5))
        mode = .globe
        liveCameraPosition = PreviewMode.globe.cameraPosition
        camera.fly(to: PreviewMode.globe.cameraPosition, options: CameraFlightOptions(duration: 1.2))

        try? await Task.sleep(for: .seconds(5))
        mode = .city
        liveCameraPosition = PreviewMode.city.cameraPosition
        camera.fly(to: PreviewMode.city.cameraPosition, options: CameraFlightOptions(duration: 1.0))

        try? await Task.sleep(for: .seconds(5))
        mode = .moscowCloseup
        liveCameraPosition = PreviewMode.moscowCloseup.cameraPosition
        camera.fly(to: PreviewMode.moscowCloseup.cameraPosition, options: CameraFlightOptions(duration: 1.0))
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

private struct CameraControlPanel: View {
    let cameraPosition: ImmersiveMapCameraPosition
    let maximumPitch: Float
    let onChange: (ImmersiveMapCameraPosition) -> Void
    @State private var draftBearingDegrees: Double?
    @State private var draftPitchDegrees: Double?
    @State private var pendingCameraUpdate: Task<Void, Never>?

    private var bearingDegrees: Double {
        CameraControlMath.degrees(fromRadians: Double(cameraPosition.bearing))
    }

    private var pitchDegrees: Double {
        CameraControlMath.degrees(fromRadians: Double(cameraPosition.pitch))
    }

    private var displayedBearingDegrees: Double {
        draftBearingDegrees ?? bearingDegrees
    }

    private var displayedPitchDegrees: Double {
        draftPitchDegrees ?? pitchDegrees
    }

    private var maximumPitchDegrees: Double {
        max(CameraControlMath.degrees(fromRadians: Double(maximumPitch)), displayedPitchDegrees)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "camera.aperture")
                    .font(.system(size: 15, weight: .semibold))
                Text("Camera")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            CameraControlSection(title: "Rotate", value: CameraControlMath.formattedDegrees(displayedBearingDegrees)) {
                HStack(spacing: 8) {
                    CameraIconButton(systemName: "rotate.left",
                                     help: "Rotate left 15 deg") {
                        adjustBearing(byDegrees: -15)
                    }

                    CameraIconButton(systemName: "location.north.line",
                                     help: "Reset north") {
                        setBearing(degrees: 0)
                    }

                    CameraIconButton(systemName: "rotate.right",
                                     help: "Rotate right 15 deg") {
                        adjustBearing(byDegrees: 15)
                    }
                }

                CameraScrubSlider(value: bearingBinding,
                                  range: -180...180,
                                  step: 1,
                                  onEditingEnded: flushPendingCameraUpdate)
            }

            Divider()
                .overlay(.white.opacity(0.2))

            CameraControlSection(title: "Tilt", value: CameraControlMath.formattedDegrees(displayedPitchDegrees)) {
                HStack(spacing: 8) {
                    CameraIconButton(systemName: "chevron.down",
                                     help: "Tilt down 5 deg") {
                        adjustPitch(byDegrees: -5)
                    }

                    CameraIconButton(systemName: "viewfinder",
                                     help: "Reset tilt") {
                        setPitch(degrees: 0)
                    }

                    CameraIconButton(systemName: "chevron.up",
                                     help: "Tilt up 5 deg") {
                        adjustPitch(byDegrees: 5)
                    }
                }

                CameraScrubSlider(value: pitchBinding,
                                  range: 0...maximumPitchDegrees,
                                  step: 1,
                                  onEditingEnded: flushPendingCameraUpdate)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 248)
        .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
        .onChange(of: cameraPosition) { _, _ in
            guard pendingCameraUpdate == nil else {
                return
            }

            draftBearingDegrees = nil
            draftPitchDegrees = nil
        }
        .onDisappear {
            pendingCameraUpdate?.cancel()
            pendingCameraUpdate = nil
        }
    }

    private var bearingBinding: Binding<Double> {
        Binding {
            displayedBearingDegrees
        } set: { newValue in
            let normalizedValue = CameraControlMath.normalizedDegrees(newValue)
            draftBearingDegrees = normalizedValue
            queueCameraUpdate(bearingDegrees: normalizedValue,
                              pitchDegrees: displayedPitchDegrees)
        }
    }

    private var pitchBinding: Binding<Double> {
        Binding {
            displayedPitchDegrees
        } set: { newValue in
            let clampedValue = CameraControlMath.clampedPitchDegrees(newValue,
                                                                     maximumPitchDegrees: maximumPitchDegrees)
            draftPitchDegrees = clampedValue
            queueCameraUpdate(bearingDegrees: displayedBearingDegrees,
                              pitchDegrees: clampedValue)
        }
    }

    private func adjustBearing(byDegrees delta: Double) {
        setBearing(degrees: displayedBearingDegrees + delta)
    }

    private func setBearing(degrees: Double) {
        let normalizedValue = CameraControlMath.normalizedDegrees(degrees)
        draftBearingDegrees = normalizedValue
        applyCameraUpdate(bearingDegrees: normalizedValue,
                          pitchDegrees: displayedPitchDegrees)
    }

    private func adjustPitch(byDegrees delta: Double) {
        setPitch(degrees: displayedPitchDegrees + delta)
    }

    private func setPitch(degrees: Double) {
        let clampedValue = CameraControlMath.clampedPitchDegrees(degrees,
                                                                 maximumPitchDegrees: maximumPitchDegrees)
        draftPitchDegrees = clampedValue
        applyCameraUpdate(bearingDegrees: displayedBearingDegrees,
                          pitchDegrees: clampedValue)
    }

    private func queueCameraUpdate(bearingDegrees: Double, pitchDegrees: Double) {
        pendingCameraUpdate?.cancel()
        pendingCameraUpdate = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(55))
            guard Task.isCancelled == false else {
                return
            }

            applyCameraUpdate(bearingDegrees: bearingDegrees,
                              pitchDegrees: pitchDegrees)
        }
    }

    private func flushPendingCameraUpdate() {
        applyCameraUpdate(bearingDegrees: displayedBearingDegrees,
                          pitchDegrees: displayedPitchDegrees)
    }

    private func applyCameraUpdate(bearingDegrees: Double, pitchDegrees: Double) {
        pendingCameraUpdate?.cancel()
        pendingCameraUpdate = nil
        onChange(cameraPosition.withCameraAngles(bearingDegrees: bearingDegrees,
                                                 pitchDegrees: pitchDegrees,
                                                 maximumPitchDegrees: maximumPitchDegrees))
    }
}

private struct CameraControlSection<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.88))
            }

            content
        }
    }
}

private struct CameraIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct CameraScrubSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let onEditingEnded: () -> Void

    private let thumbSize: CGFloat = 22
    private let trackHeight: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = max(1, proxy.size.width - thumbSize)
            let progress = progress(for: value)
            let thumbCenterX = thumbSize / 2 + trackWidth * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color(red: 0.02, green: 0.55, blue: 0.95))
                    .frame(width: max(thumbCenterX, thumbSize / 2), height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 2)
                    .offset(x: thumbCenterX - thumbSize / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        value = steppedValue(for: gesture.location.x,
                                             trackWidth: trackWidth)
                    }
                    .onEnded { gesture in
                        value = steppedValue(for: gesture.location.x,
                                             trackWidth: trackWidth)
                        onEditingEnded()
                    }
            )
        }
        .frame(height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera slider")
        .accessibilityValue(CameraControlMath.formattedDegrees(value))
    }

    private func progress(for value: Double) -> CGFloat {
        let lower = range.lowerBound
        let upper = range.upperBound
        guard upper > lower else {
            return 0
        }

        let clampedValue = min(max(value, lower), upper)
        return CGFloat((clampedValue - lower) / (upper - lower))
    }

    private func steppedValue(for locationX: CGFloat, trackWidth: CGFloat) -> Double {
        let rawProgress = Double(min(max(0, locationX - thumbSize / 2), trackWidth) / trackWidth)
        let rawValue = range.lowerBound + (range.upperBound - range.lowerBound) * rawProgress
        let snappedValue = step > 0 ? (rawValue / step).rounded() * step : rawValue
        return min(max(snappedValue, range.lowerBound), range.upperBound)
    }
}

private enum CameraControlMath {
    static func degrees(fromRadians radians: Double) -> Double {
        let degrees = radians * 180 / .pi
        return normalizedDegrees(degrees)
    }

    static func radians(fromDegrees degrees: Double) -> Float {
        Float(normalizedDegrees(degrees) * .pi / 180)
    }

    static func pitchRadians(fromDegrees degrees: Double, maximumPitchDegrees: Double) -> Float {
        Float(clampedPitchDegrees(degrees, maximumPitchDegrees: maximumPitchDegrees) * .pi / 180)
    }

    static func formattedDegrees(_ degrees: Double) -> String {
        "\(Int(degrees.rounded())) deg"
    }

    static func clampedPitchDegrees(_ degrees: Double, maximumPitchDegrees: Double) -> Double {
        min(max(0, degrees), maximumPitchDegrees)
    }

    static func normalizedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 {
            value -= 360
        } else if value < -180 {
            value += 360
        }
        return value
    }
}

private extension ImmersiveMapCameraPosition {
    func withCameraAngles(bearingDegrees: Double,
                          pitchDegrees: Double,
                          maximumPitchDegrees: Double) -> ImmersiveMapCameraPosition {
        ImmersiveMapCameraPosition(
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            zoom: zoom,
            bearing: CameraControlMath.radians(fromDegrees: bearingDegrees),
            pitch: CameraControlMath.pitchRadians(fromDegrees: pitchDegrees,
                                                  maximumPitchDegrees: maximumPitchDegrees)
        )
    }
}

private enum PreviewMode: String {
    case city
    case globe
    case moscowCloseup

    static var initial: PreviewMode {
        let rawValue = ProcessInfo.processInfo.environment["IMMERSIVE_MAP_DEMO_MODE"]
        return rawValue.flatMap(PreviewMode.init(rawValue:)) ?? .city
    }

    static var shouldAutoCycle: Bool {
        ProcessInfo.processInfo.environment["IMMERSIVE_MAP_DEMO_MODE"] == nil
    }

    var title: String {
        switch self {
        case .city:
            return "ImmersiveMap city view"
        case .globe:
            return "ImmersiveMap globe view"
        case .moscowCloseup:
            return "ImmersiveMap Moscow close-up"
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
        case .moscowCloseup:
            return ImmersiveMapCameraPosition(
                latitudeDegrees: 55.7520,
                longitudeDegrees: 37.6175,
                zoom: 16.6,
                bearing: -.pi / 7,
                pitch: .pi / 4
            )
        }
    }
}
