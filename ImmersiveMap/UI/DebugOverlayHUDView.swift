// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

import UIKit

final class DebugOverlayHUDView: UIView {
    private enum Layout {
        static let coordinateFontScale: CGFloat = 0.56
        static let diagnosticsFontScale: CGFloat = 0.50
        static let contentInset: CGFloat = 8.0
        static let headerHeight: CGFloat = 30.0
        static let controlRowHeight: CGFloat = 30.0
        static let controlSpacing: CGFloat = 6.0
        static let cornerRadius: CGFloat = 8.0
        static let backgroundAlpha: CGFloat = 0.46
        static let expandedMinimumWidth: CGFloat = 260.0
        static let collapsedWidth: CGFloat = 136.0
        static let maximumWidth: CGFloat = 720.0
    }

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let collapseButton = UIButton(type: .system)
    private let axesLabel = UILabel()
    private let axesSwitch = UISwitch()
    private let tileLayersLabel = UILabel()
    private let tileLayersSwitch = UISwitch()
    private let surfaceModeButton = UIButton(type: .system)
    private let zoomLabel = UILabel()
    private let latLonLabel = UILabel()
    private let diagnosticsLabel = UILabel()
    private var snapshot: DebugOverlayHUDSnapshot?
    private var isPanelEnabled = false
    private var isCollapsed = false

    var onAxesEnabledChanged: ((Bool) -> Void)?
    var onTileLayersEnabledChanged: ((Bool) -> Void)?
    var onSurfaceModeSwitchRequested: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isOpaque = false
        isUserInteractionEnabled = true

        containerView.isOpaque = false
        containerView.isUserInteractionEnabled = true
        containerView.backgroundColor = UIColor.black.withAlphaComponent(Layout.backgroundAlpha)
        containerView.layer.cornerRadius = Layout.cornerRadius
        containerView.layer.masksToBounds = true
        addSubview(containerView)

        titleLabel.text = "Debug"
        titleLabel.textColor = .white
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        containerView.addSubview(titleLabel)

        collapseButton.tintColor = .white
        collapseButton.addTarget(self, action: #selector(toggleCollapsed), for: .touchUpInside)
        containerView.addSubview(collapseButton)

        configureControlLabel(axesLabel, text: "Axes")
        configureControlLabel(tileLayersLabel, text: "Tile layers")
        axesSwitch.addTarget(self, action: #selector(axesSwitchChanged), for: .valueChanged)
        tileLayersSwitch.addTarget(self, action: #selector(tileLayersSwitchChanged), for: .valueChanged)
        containerView.addSubview(axesLabel)
        containerView.addSubview(axesSwitch)
        containerView.addSubview(tileLayersLabel)
        containerView.addSubview(tileLayersSwitch)
        configureSurfaceModeButton()
        containerView.addSubview(surfaceModeButton)

        [zoomLabel, latLonLabel, diagnosticsLabel].forEach { label in
            label.numberOfLines = 0
            label.lineBreakMode = .byCharWrapping
            label.adjustsFontSizeToFitWidth = false
            containerView.addSubview(label)
        }
        updateCollapseButtonImage()
        updateVisibility()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: DebugOverlayHUDSnapshot?) {
        self.snapshot = snapshot
        updateText()
        updateVisibility()
        setNeedsLayout()
    }

    func apply(isDebugPanelEnabled: Bool,
               controls: DebugOverlayControlSnapshot) {
        isPanelEnabled = isDebugPanelEnabled
        axesSwitch.setOn(controls.axesEnabled, animated: false)
        tileLayersSwitch.setOn(controls.tileLayersEnabled, animated: false)
        updateVisibility()
        setNeedsLayout()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isHidden == false else { return false }
        return containerView.frame.contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let snapshot else { return }

        let scale = max(window?.screen.scale ?? UIScreen.main.scale, 1.0)
        let left = CGFloat(snapshot.leftPadding) / scale
        let top = CGFloat(snapshot.topPadding) / scale
        let sectionSpacing = CGFloat(snapshot.sectionSpacing) / scale
        let maxPanelWidth = min(Layout.maximumWidth, max(bounds.width - left - Layout.contentInset, Layout.collapsedWidth))

        if isCollapsed {
            containerView.frame = CGRect(x: left - Layout.contentInset,
                                         y: top - Layout.headerHeight - Layout.contentInset,
                                         width: Layout.collapsedWidth,
                                         height: Layout.headerHeight)
            layoutHeader(width: Layout.collapsedWidth)
            return
        }

        let maxContentWidth = max(maxPanelWidth - Layout.contentInset * 2, 1)
        let constrainedSize = CGSize(width: maxContentWidth,
                                     height: CGFloat.greatestFiniteMagnitude)

        let zoomSize = zoomLabel.sizeThatFits(constrainedSize)
        let latLonSize = latLonLabel.sizeThatFits(constrainedSize)
        let diagnosticsSize = diagnosticsLabel.sizeThatFits(constrainedSize)
        let textContentWidth = min(max(zoomSize.width, latLonSize.width, diagnosticsSize.width), maxContentWidth)
        let contentWidth = max(Layout.expandedMinimumWidth, textContentWidth)
        let controlsHeight = Layout.controlRowHeight * 3 + Layout.controlSpacing * 2
        let contentHeight = Layout.headerHeight
            + Layout.contentInset
            + controlsHeight
            + sectionSpacing
            + zoomSize.height
            + latLonSize.height
            + sectionSpacing
            + diagnosticsSize.height
            + Layout.contentInset
        let containerSize = CGSize(width: contentWidth + Layout.contentInset * 2,
                                   height: contentHeight)

        containerView.frame = CGRect(x: left - Layout.contentInset,
                                     y: top - zoomSize.height - Layout.contentInset,
                                     width: containerSize.width,
                                     height: containerSize.height)
        layoutHeader(width: containerSize.width)

        let switchSize = axesSwitch.sizeThatFits(.zero)
        let labelWidth = contentWidth - switchSize.width - Layout.controlSpacing
        let controlsTop = Layout.headerHeight + Layout.contentInset
        axesLabel.frame = CGRect(x: Layout.contentInset,
                                 y: controlsTop,
                                 width: labelWidth,
                                 height: Layout.controlRowHeight)
        axesSwitch.frame = CGRect(x: containerSize.width - Layout.contentInset - switchSize.width,
                                  y: controlsTop + (Layout.controlRowHeight - switchSize.height) / 2,
                                  width: switchSize.width,
                                  height: switchSize.height)
        tileLayersLabel.frame = CGRect(x: Layout.contentInset,
                                       y: axesLabel.frame.maxY + Layout.controlSpacing,
                                       width: labelWidth,
                                       height: Layout.controlRowHeight)
        tileLayersSwitch.frame = CGRect(x: containerSize.width - Layout.contentInset - switchSize.width,
                                        y: tileLayersLabel.frame.minY + (Layout.controlRowHeight - switchSize.height) / 2,
                                        width: switchSize.width,
                                        height: switchSize.height)
        surfaceModeButton.frame = CGRect(x: Layout.contentInset,
                                         y: tileLayersLabel.frame.maxY + Layout.controlSpacing,
                                         width: contentWidth,
                                         height: Layout.controlRowHeight)

        let textTop = surfaceModeButton.frame.maxY + sectionSpacing
        zoomLabel.frame = CGRect(x: Layout.contentInset,
                                 y: textTop,
                                 width: contentWidth,
                                 height: zoomSize.height)
        latLonLabel.frame = CGRect(x: Layout.contentInset,
                                   y: zoomLabel.frame.maxY,
                                   width: contentWidth,
                                   height: latLonSize.height)
        diagnosticsLabel.frame = CGRect(x: Layout.contentInset,
                                        y: latLonLabel.frame.maxY + sectionSpacing,
                                        width: contentWidth,
                                        height: diagnosticsSize.height)
    }

    private func layoutHeader(width: CGFloat) {
        let buttonSide = Layout.headerHeight
        titleLabel.frame = CGRect(x: Layout.contentInset,
                                  y: 0,
                                  width: width - Layout.contentInset * 2 - buttonSide,
                                  height: Layout.headerHeight)
        collapseButton.frame = CGRect(x: width - Layout.contentInset - buttonSide,
                                      y: 0,
                                      width: buttonSide,
                                      height: buttonSide)
        let contentViews = [axesLabel, axesSwitch, tileLayersLabel, tileLayersSwitch, surfaceModeButton, zoomLabel, latLonLabel, diagnosticsLabel]
        contentViews.forEach { $0.isHidden = isCollapsed }
    }

    private func updateText() {
        guard let snapshot else {
            zoomLabel.attributedText = nil
            latLonLabel.attributedText = nil
            diagnosticsLabel.attributedText = nil
            return
        }

        let scale = max(window?.screen.scale ?? UIScreen.main.scale, 1.0)
        let coordinateFontSize = max(1, CGFloat(snapshot.coordinateScale) * Layout.coordinateFontScale / scale)
        let diagnosticsFontSize = max(1, CGFloat(snapshot.diagnosticsScale) * Layout.diagnosticsFontScale / scale)
        let color = UIColor.white

        zoomLabel.attributedText = attributedText(snapshot.coordinateLines.zoom,
                                                 fontSize: coordinateFontSize,
                                                 color: color)
        latLonLabel.attributedText = attributedText(snapshot.coordinateLines.latLon,
                                                   fontSize: coordinateFontSize,
                                                   color: color)
        diagnosticsLabel.attributedText = attributedText(snapshot.diagnosticsLines.joined(separator: "\n"),
                                                        fontSize: diagnosticsFontSize,
                                                        color: color)
    }

    private func updateVisibility() {
        isHidden = isPanelEnabled == false || snapshot == nil
    }

    private func configureControlLabel(_ label: UILabel, text: String) {
        label.text = text
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 13, weight: .medium)
    }

    private func configureSurfaceModeButton() {
        surfaceModeButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        surfaceModeButton.layer.cornerRadius = 6
        surfaceModeButton.layer.masksToBounds = true
        surfaceModeButton.addTarget(self, action: #selector(surfaceModeButtonTapped), for: .touchUpInside)
        if #available(iOS 15.0, *) {
            var configuration = UIButton.Configuration.plain()
            configuration.title = "Switch globe / flat"
            configuration.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            configuration.imagePadding = 6
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
            configuration.baseForegroundColor = .white
            configuration.background.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            configuration.cornerStyle = .fixed
            surfaceModeButton.configuration = configuration
        } else {
            surfaceModeButton.setTitle("Switch globe / flat", for: .normal)
            surfaceModeButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath"), for: .normal)
            surfaceModeButton.tintColor = .white
            surfaceModeButton.setTitleColor(.white, for: .normal)
            surfaceModeButton.backgroundColor = UIColor.white.withAlphaComponent(0.12)
            surfaceModeButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        }
    }

    private func updateCollapseButtonImage() {
        let imageName = isCollapsed ? "chevron.down" : "chevron.up"
        collapseButton.setImage(UIImage(systemName: imageName), for: .normal)
        collapseButton.accessibilityLabel = isCollapsed ? "Expand debug panel" : "Collapse debug panel"
    }

    @objc private func toggleCollapsed() {
        isCollapsed.toggle()
        updateCollapseButtonImage()
        setNeedsLayout()
    }

    @objc private func axesSwitchChanged() {
        onAxesEnabledChanged?(axesSwitch.isOn)
    }

    @objc private func tileLayersSwitchChanged() {
        onTileLayersEnabledChanged?(tileLayersSwitch.isOn)
    }

    @objc private func surfaceModeButtonTapped() {
        onSurfaceModeSwitchRequested?()
    }

    private func attributedText(_ text: String,
                                fontSize: CGFloat,
                                color: UIColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: color
            ]
        )
    }
}

#if DEBUG
extension DebugOverlayHUDView {
    func simulateSurfaceModeSwitchForTesting() {
        surfaceModeButtonTapped()
    }
}
#endif

#endif
