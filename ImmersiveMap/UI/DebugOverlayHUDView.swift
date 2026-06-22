// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

#if canImport(UIKit)

import UIKit

final class DebugOverlayHUDView: UIView {
    private enum SelectedTab: Int {
        case stats = 0
        case atlas = 1
    }

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
    private let wireframeLabel = UILabel()
    private let wireframeSwitch = UISwitch()
    private let surfaceModeButton = UIButton(type: .system)
    private let tabControl = UISegmentedControl(items: ["Stats", "Atlas"])
    private let zoomLabel = UILabel()
    private let latLonLabel = UILabel()
    private let diagnosticsLabel = UILabel()
    private let atlasScrollView = UIScrollView()
    private let atlasLayoutView = DebugOverlayAtlasLayoutView()
    private let atlasDetailsLabel = UILabel()
    private var snapshot: DebugOverlayHUDSnapshot?
    private var isPanelEnabled = false
    private var isCollapsed = false
    private var selectedTab: SelectedTab = .stats

    var onAxesEnabledChanged: ((Bool) -> Void)?
    var onTileLayersEnabledChanged: ((Bool) -> Void)?
    var onWireframeEnabledChanged: ((Bool) -> Void)?
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
        configureControlLabel(wireframeLabel, text: "Wireframe")
        axesSwitch.addTarget(self, action: #selector(axesSwitchChanged), for: .valueChanged)
        tileLayersSwitch.addTarget(self, action: #selector(tileLayersSwitchChanged), for: .valueChanged)
        wireframeSwitch.addTarget(self, action: #selector(wireframeSwitchChanged), for: .valueChanged)
        containerView.addSubview(axesLabel)
        containerView.addSubview(axesSwitch)
        containerView.addSubview(tileLayersLabel)
        containerView.addSubview(tileLayersSwitch)
        containerView.addSubview(wireframeLabel)
        containerView.addSubview(wireframeSwitch)
        configureSurfaceModeButton()
        containerView.addSubview(surfaceModeButton)
        tabControl.selectedSegmentIndex = SelectedTab.stats.rawValue
        tabControl.addTarget(self, action: #selector(tabControlChanged), for: .valueChanged)
        containerView.addSubview(tabControl)

        [zoomLabel, latLonLabel, diagnosticsLabel].forEach { label in
            label.numberOfLines = 0
            label.lineBreakMode = .byCharWrapping
            label.adjustsFontSizeToFitWidth = false
            containerView.addSubview(label)
        }
        atlasDetailsLabel.numberOfLines = 0
        atlasDetailsLabel.lineBreakMode = .byWordWrapping
        atlasDetailsLabel.adjustsFontSizeToFitWidth = false
        atlasScrollView.backgroundColor = .clear
        atlasScrollView.alwaysBounceVertical = false
        atlasScrollView.showsHorizontalScrollIndicator = false
        atlasScrollView.showsVerticalScrollIndicator = true
        containerView.addSubview(atlasScrollView)
        atlasScrollView.addSubview(atlasLayoutView)
        atlasScrollView.addSubview(atlasDetailsLabel)
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
        wireframeSwitch.setOn(controls.wireframeEnabled, animated: false)
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
        let atlasDetailsSize = atlasDetailsLabel.sizeThatFits(constrainedSize)
        let atlasPreviewHeight = atlasLayoutView.preferredHeight(forWidth: maxContentWidth)
        let textContentWidth = min(max(zoomSize.width,
                                       latLonSize.width,
                                       diagnosticsSize.width,
                                       atlasDetailsSize.width), maxContentWidth)
        let contentWidth = max(Layout.expandedMinimumWidth, textContentWidth)
        let controlsHeight = Layout.controlRowHeight * 5 + Layout.controlSpacing * 4
        let statsBodyHeight = zoomSize.height
            + latLonSize.height
            + sectionSpacing
            + diagnosticsSize.height
        let atlasBodyHeight = atlasPreviewHeight
            + sectionSpacing
            + atlasDetailsSize.height
        let panelY = top - zoomSize.height - Layout.contentInset
        let chromeHeight = Layout.headerHeight
            + Layout.contentInset
            + controlsHeight
            + sectionSpacing
            + Layout.contentInset
        let visibleAtlasBodyHeight = DebugOverlayPanelLayout.visibleBodyHeight(
            preferredBodyHeight: atlasBodyHeight,
            viewportHeight: bounds.height,
            panelMinY: panelY,
            chromeHeight: chromeHeight,
            minimumBodyHeight: 48
        )
        let bodyHeight = selectedTab == .atlas ? visibleAtlasBodyHeight : statsBodyHeight
        let contentHeight = Layout.headerHeight
            + Layout.contentInset
            + controlsHeight
            + sectionSpacing
            + bodyHeight
            + Layout.contentInset
        let containerSize = CGSize(width: contentWidth + Layout.contentInset * 2,
                                   height: contentHeight)

        containerView.frame = CGRect(x: left - Layout.contentInset,
                                     y: panelY,
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
        wireframeLabel.frame = CGRect(x: Layout.contentInset,
                                      y: tileLayersLabel.frame.maxY + Layout.controlSpacing,
                                      width: labelWidth,
                                      height: Layout.controlRowHeight)
        wireframeSwitch.frame = CGRect(x: containerSize.width - Layout.contentInset - switchSize.width,
                                       y: wireframeLabel.frame.minY + (Layout.controlRowHeight - switchSize.height) / 2,
                                       width: switchSize.width,
                                       height: switchSize.height)
        surfaceModeButton.frame = CGRect(x: Layout.contentInset,
                                         y: wireframeLabel.frame.maxY + Layout.controlSpacing,
                                         width: contentWidth,
                                         height: Layout.controlRowHeight)
        tabControl.frame = CGRect(x: Layout.contentInset,
                                  y: surfaceModeButton.frame.maxY + Layout.controlSpacing,
                                  width: contentWidth,
                                  height: Layout.controlRowHeight)

        let textTop = tabControl.frame.maxY + sectionSpacing
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
        atlasScrollView.frame = CGRect(x: Layout.contentInset,
                                       y: textTop,
                                       width: contentWidth,
                                       height: visibleAtlasBodyHeight)
        atlasLayoutView.frame = CGRect(x: 0,
                                       y: 0,
                                       width: contentWidth,
                                       height: atlasPreviewHeight)
        atlasDetailsLabel.frame = CGRect(x: 0,
                                         y: atlasLayoutView.frame.maxY + sectionSpacing,
                                         width: contentWidth,
                                         height: atlasDetailsSize.height)
        atlasScrollView.contentSize = CGSize(width: contentWidth,
                                             height: atlasBodyHeight)
        atlasScrollView.isScrollEnabled = atlasBodyHeight > visibleAtlasBodyHeight + 0.5
        updateContentVisibility()
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
        updateContentVisibility()
    }

    private func updateText() {
        guard let snapshot else {
            zoomLabel.attributedText = nil
            latLonLabel.attributedText = nil
            diagnosticsLabel.attributedText = nil
            atlasDetailsLabel.attributedText = nil
            atlasLayoutView.apply(pages: [])
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
        atlasLayoutView.apply(pages: snapshot.atlasPages)
        atlasDetailsLabel.attributedText = attributedText(atlasDetailsText(pages: snapshot.atlasPages),
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

    private func updateContentVisibility() {
        let isContentHidden = isCollapsed
        let isAtlasVisible = selectedTab == .atlas && isContentHidden == false
        let isStatsVisible = selectedTab == .stats && isContentHidden == false
        [axesLabel, axesSwitch, tileLayersLabel, tileLayersSwitch, wireframeLabel, wireframeSwitch, surfaceModeButton, tabControl].forEach {
            $0.isHidden = isContentHidden
        }
        [zoomLabel, latLonLabel, diagnosticsLabel].forEach {
            $0.isHidden = isStatsVisible == false
        }
        atlasScrollView.isHidden = isAtlasVisible == false
    }

    private func atlasDetailsText(pages: [GlobeAtlasDebugPage]) -> String {
        guard pages.isEmpty == false else {
            return "atlas pages: none"
        }

        let allocationCount = pages.reduce(0) { $0 + $1.allocations.count }
        let pageSummary = pages
            .map { "p\($0.pageIndex):\($0.allocations.count)" }
            .joined(separator: " ")
        let previewLines = pages.flatMap { page in
            page.allocations.prefix(4).map { allocation in
                return "p\(page.pageIndex) d\(allocation.atlasDepth.rawValue) " +
                    "src z\(allocation.sourceTile.z)/\(allocation.sourceTile.x)/\(allocation.sourceTile.y) " +
                    "dst z\(allocation.targetTile.z)/\(allocation.targetTile.x)/\(allocation.targetTile.y)" +
                    Self.allocationStateSuffix(allocation)
            }
        }
        return (["atlas pages:\(pages.count) alloc:\(allocationCount) \(pageSummary)"] + previewLines)
            .joined(separator: "\n")
    }

    private static func allocationStateSuffix(_ allocation: GlobeAtlasDebugAllocation) -> String {
        switch allocation.lodKind {
        case .exact:
            return allocation.sourceTile == allocation.targetTile ? "" : " retained"
        case .coarseSubstitute:
            return " coarse"
        case .retainedReplacement:
            return " retained"
        }
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

    @objc private func wireframeSwitchChanged() {
        onWireframeEnabledChanged?(wireframeSwitch.isOn)
    }

    @objc private func surfaceModeButtonTapped() {
        onSurfaceModeSwitchRequested?()
    }

    @objc private func tabControlChanged() {
        selectedTab = SelectedTab(rawValue: tabControl.selectedSegmentIndex) ?? .stats
        updateContentVisibility()
        setNeedsLayout()
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

private final class DebugOverlayAtlasLayoutView: UIView {
    private enum Layout {
        static let pageLabelHeight: CGFloat = 16
        static let pageSpacing: CGFloat = 10
        static let borderWidth: CGFloat = 1
    }

    private var pages: [GlobeAtlasDebugPage] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var pageCount: Int {
        pages.count
    }

    func apply(pages: [GlobeAtlasDebugPage]) {
        self.pages = pages
        setNeedsDisplay()
    }

    func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        guard pages.isEmpty == false else {
            return 48
        }

        let pageSide = Self.pageSide(forWidth: width)
        return CGFloat(pages.count) * (Layout.pageLabelHeight + pageSide)
            + CGFloat(max(0, pages.count - 1)) * Layout.pageSpacing
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        guard pages.isEmpty == false else {
            drawEmptyState(in: rect)
            return
        }

        let pageSide = Self.pageSide(forWidth: bounds.width)
        var y = bounds.minY
        for page in pages {
            drawPageLabel(page: page, y: y)
            y += Layout.pageLabelHeight
            let pageRect = CGRect(x: bounds.minX,
                                  y: y,
                                  width: pageSide,
                                  height: pageSide)
            drawPage(page, in: pageRect, context: context)
            y += pageSide + Layout.pageSpacing
        }
    }

    private static func pageSide(forWidth width: CGFloat) -> CGFloat {
        min(max(width, 1), 260)
    }

    private func drawEmptyState(in rect: CGRect) {
        let text = "No globe atlas pages"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.72)
        ]
        text.draw(in: rect.insetBy(dx: 2, dy: 14), withAttributes: attributes)
    }

    private func drawPageLabel(page: GlobeAtlasDebugPage, y: CGFloat) {
        let text = "page \(page.pageIndex) slots \(page.allocations.count)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.9)
        ]
        text.draw(in: CGRect(x: bounds.minX, y: y, width: bounds.width, height: Layout.pageLabelHeight),
                  withAttributes: attributes)
    }

    private func drawPage(_ page: GlobeAtlasDebugPage,
                          in pageRect: CGRect,
                          context: CGContext) {
        context.setFillColor(UIColor.white.withAlphaComponent(0.06).cgColor)
        context.fill(pageRect)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(Layout.borderWidth)
        context.stroke(pageRect)

        for allocation in page.allocations {
            drawAllocation(allocation, pageRect: pageRect, context: context)
        }
    }

    private func drawAllocation(_ allocation: GlobeAtlasDebugAllocation,
                                pageRect: CGRect,
                                context: CGContext) {
        let slots = CGFloat(max(allocation.slotsPerSide, 1))
        let cell = pageRect.width / slots
        let displayRow = CGFloat(max(0, allocation.slotsPerSide - 1 - allocation.slotRow))
        let allocationRect = CGRect(x: pageRect.minX + CGFloat(allocation.slotColumn) * cell,
                                    y: pageRect.minY + displayRow * cell,
                                    width: cell,
                                    height: cell)
        let color = color(for: allocation)
        context.setFillColor(color.withAlphaComponent(0.26).cgColor)
        context.fill(allocationRect)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(allocation.isFallback ? 2 : 1)
        context.stroke(allocationRect.insetBy(dx: 0.5, dy: 0.5))
        drawAllocationLabel(allocation, in: allocationRect)
    }

    private func drawAllocationLabel(_ allocation: GlobeAtlasDebugAllocation,
                                     in allocationRect: CGRect) {
        let inset = min(max(allocationRect.width * 0.08, 2), 5)
        let labelRect = allocationRect.insetBy(dx: inset, dy: inset)
        guard labelRect.width >= 10, labelRect.height >= 8 else { return }

        let fontSize = min(10, max(6, labelRect.height * 0.28))
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.82)
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.95),
            .shadow: shadow
        ]
        allocation.atlasPreviewLabel.draw(in: labelRect, withAttributes: attributes)
    }

    private func color(for allocation: GlobeAtlasDebugAllocation) -> UIColor {
        if allocation.isFallback {
            return UIColor.systemOrange
        }

        switch allocation.atlasDepth {
        case .depth0:
            return UIColor.systemRed
        case .depth1:
            return UIColor.systemYellow
        case .depth2:
            return UIColor.systemGreen
        case .depth3:
            return UIColor.systemTeal
        case .depth4:
            return UIColor.systemBlue
        }
    }
}

#if DEBUG
extension DebugOverlayHUDView {
    func simulateSurfaceModeSwitchForTesting() {
        surfaceModeButtonTapped()
    }

    func simulateAtlasTabSelectionForTesting() {
        tabControl.selectedSegmentIndex = SelectedTab.atlas.rawValue
        tabControlChanged()
    }

    var isAtlasTabSelectedForTesting: Bool {
        selectedTab == .atlas
    }

    var atlasPreviewPageCountForTesting: Int {
        atlasLayoutView.pageCount
    }

    var debugPanelFrameForTesting: CGRect {
        containerView.frame
    }

    var isAtlasScrollEnabledForTesting: Bool {
        atlasScrollView.isScrollEnabled
    }
}
#endif

#endif
