// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

import UIKit

final class DebugOverlayHUDView: UIView {
    private enum Layout {
        static let coordinateFontScale: CGFloat = 0.56
        static let diagnosticsFontScale: CGFloat = 0.50
        static let contentInset: CGFloat = 8.0
        static let cornerRadius: CGFloat = 8.0
        static let backgroundAlpha: CGFloat = 0.46
    }

    private let containerView = UIView()
    private let zoomLabel = UILabel()
    private let latLonLabel = UILabel()
    private let diagnosticsLabel = UILabel()
    private var snapshot: DebugOverlayHUDSnapshot?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        isOpaque = false
        isUserInteractionEnabled = false

        containerView.isOpaque = false
        containerView.isUserInteractionEnabled = false
        containerView.backgroundColor = UIColor.black.withAlphaComponent(Layout.backgroundAlpha)
        containerView.layer.cornerRadius = Layout.cornerRadius
        containerView.layer.masksToBounds = true
        addSubview(containerView)

        [zoomLabel, latLonLabel, diagnosticsLabel].forEach { label in
            label.numberOfLines = 0
            label.lineBreakMode = .byClipping
            label.adjustsFontSizeToFitWidth = false
            containerView.addSubview(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(snapshot: DebugOverlayHUDSnapshot?) {
        self.snapshot = snapshot
        isHidden = snapshot == nil
        updateText()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let snapshot else { return }

        let scale = max(window?.screen.scale ?? UIScreen.main.scale, 1.0)
        let left = CGFloat(snapshot.leftPadding) / scale
        let top = CGFloat(snapshot.topPadding) / scale
        let sectionSpacing = CGFloat(snapshot.sectionSpacing) / scale
        let unconstrainedSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                       height: CGFloat.greatestFiniteMagnitude)

        let zoomSize = zoomLabel.sizeThatFits(unconstrainedSize)
        let latLonSize = latLonLabel.sizeThatFits(unconstrainedSize)
        let diagnosticsSize = diagnosticsLabel.sizeThatFits(unconstrainedSize)
        let contentWidth = max(zoomSize.width, latLonSize.width, diagnosticsSize.width)
        let contentHeight = zoomSize.height + latLonSize.height + sectionSpacing + diagnosticsSize.height
        let containerSize = CGSize(width: contentWidth + Layout.contentInset * 2,
                                   height: contentHeight + Layout.contentInset * 2)

        containerView.frame = CGRect(x: left - Layout.contentInset,
                                     y: top - zoomSize.height - Layout.contentInset,
                                     width: containerSize.width,
                                     height: containerSize.height)

        zoomLabel.frame = CGRect(x: Layout.contentInset,
                                 y: Layout.contentInset,
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

#endif
