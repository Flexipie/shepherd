import AppKit
import Observation
import ShepherdCore
import ShepherdUI
import SwiftUI

/// The notch surface: one black shape around the notch that is the paw ear when the herd is
/// quiet, the needs-you pill when a module offers a notch item, and the panel while hovered.
///
/// The SwiftUI view spans a fixed canvas (every state at its largest) and never moves on screen;
/// the window is only as large as the shape needs. Before a morph the window grows to cover both
/// shapes, and once the animation ends it shrinks to the new one, so the transparent rest of the
/// canvas never sits over the menu bar. On a display without a notch there is no ear and no
/// hover, only the floating pill.
@MainActor
final class NotchSurfaceController: NSObject, NSWindowDelegate {
    static let expandDelay: Duration = .milliseconds(120)
    static let collapseDelay: Duration = .milliseconds(300)

    private let registry: ModuleRegistry
    private let content: PanelContentSource
    private let actions: any AgentActions
    private let model = NotchSurfaceModel()
    private let floating = FloatingPill()
    private var geometry: NotchGeometry?
    private var panel: NotchSurfacePanel?
    private var hosting: NotchHostingView?
    private var expanded = false
    private var hoverTask: Task<Void, Never>?
    /// Bumps on every render, so a stale observation callback is ignored.
    private var renderToken = 0
    /// Bumps on every morph, so only the latest one shrinks the window when it ends.
    private var morphToken = 0
    private var screenObserver: NSObjectProtocol?

    init(registry: ModuleRegistry, content: PanelContentSource, actions: any AgentActions) {
        self.registry = registry
        self.content = content
        self.actions = actions
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        rebuild()
    }

    /// Closes the panel back into the notch.
    func collapse() {
        cancelHover()
        guard expanded else { return }
        expanded = false
        if let panel, panel.isKeyWindow {
            // Hands key back to the app the user was in, which stayed active throughout.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        render()
    }

    private func expand() {
        cancelHover()
        guard !expanded, geometry?.metrics != nil else { return }
        expanded = true
        render()
    }

    // MARK: Building

    private func rebuild() {
        let next = NotchGeometry.current()
        guard next != geometry || panel == nil && next?.metrics != nil else { return }
        tearDown()
        geometry = next
        if let next, let metrics = next.metrics { build(metrics, panelMaxHeight: next.panelMaxHeight) }
        render()
    }

    private func build(_ metrics: NotchMetrics, panelMaxHeight: CGFloat?) {
        if model.expandedHeight == 0 { model.expandedHeight = metrics.notchHeight + 240 }
        let panel = NotchSurfacePanel()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.collapse() }
        let root = NotchSurfaceRoot(
            model: model, metrics: metrics, panelMaxHeight: panelMaxHeight,
            perform: { [weak self] action in self?.perform(action) },
            onExpand: { [weak self] in self?.expand() },
            onExpandedHeight: { [weak self] height in
                // After the layout pass that measured it.
                Task { @MainActor in self?.setExpandedHeight(height) }
            })
        let hosting = NotchHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.autoresizingMask = []
        hosting.setFrameSize(metrics.canvas.size)
        hosting.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        let container = NSView()
        container.autoresizesSubviews = false
        container.addSubview(hosting)
        panel.contentView = container
        self.panel = panel
        self.hosting = hosting
    }

    private func tearDown() {
        cancelHover()
        expanded = false
        floating.hide()
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        hosting = nil
        model.mode = nil
    }

    // MARK: Rendering

    /// Re-renders when anything the current mode reads changes. Only the expanded mode reads the
    /// panel's content, so a quiet ear redraws only when the status contribution does.
    private func render() {
        renderToken += 1
        let token = renderToken
        let mode = withObservationTracking {
            currentMode()
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, token == self.renderToken else { return }
                self.render()
            }
        }
        guard let geometry else { return }
        if geometry.metrics == nil {
            showFloating(mode, in: geometry.floatingFrame)
        } else {
            apply(mode)
        }
    }

    private func currentMode() -> NotchSurfaceMode {
        if expanded { return .expanded(content.current()) }
        if let item = registry.modules.lazy.compactMap(\.notch).first { return .alert(item) }
        return .ear(registry.modules.lazy.compactMap(\.status).first
            ?? StatusContribution(symbol: "pawprint", accessibilityLabel: "Shepherd"))
    }

    private func showFloating(_ mode: NotchSurfaceMode, in frame: NSRect) {
        guard case .alert(let item) = mode else { return floating.hide() }
        floating.show(item, in: frame) { [weak self] in self?.actions.jump(to: item.agent.id) }
    }

    private func apply(_ mode: NotchSurfaceMode) {
        guard let panel, mode != model.mode else { return }
        guard let current = model.mode else {
            // First appearance: no morph.
            model.mode = mode
            if let outline = outline() { setWindowFrame(outline) }
            panel.orderFrontRegardless()
            return
        }
        if current.kind == mode.kind {
            // Same shape, new content: the views animate their own changes.
            model.mode = mode
        } else {
            morph { self.model.mode = mode }
        }
    }

    private func setExpandedHeight(_ height: CGFloat) {
        guard abs(height - model.expandedHeight) > 0.5 else { return }
        if model.mode?.kind == .expanded {
            morph { self.model.expandedHeight = height }
        } else {
            model.expandedHeight = height
        }
    }

    /// Changes the shape inside a spring (a crossfade with Reduce Motion, which the view applies),
    /// growing the window first so the shape can animate inside it, and shrinking it after.
    private func morph(_ change: @escaping () -> Void) {
        guard let panel else { return }
        morphToken += 1
        let token = morphToken
        let animation: Animation = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeInOut(duration: 0.15) : .spring(duration: 0.35, bounce: 0.12)
        withAnimation(animation, completionCriteria: .removed) {
            change()
        } completion: { [weak self] in
            guard let self, token == self.morphToken, let outline = self.outline() else { return }
            self.setWindowFrame(outline)
        }
        if let outline = outline() { setWindowFrame(panel.frame.union(outline)) }
    }

    // MARK: Frames

    /// The current shape with its flares, in screen coordinates.
    private func outline() -> NSRect? {
        guard let geometry, let metrics = geometry.metrics, let kind = model.mode?.kind else { return nil }
        return geometry.screenRect(metrics.outline(kind, expandedHeight: model.expandedHeight))
    }

    /// The current shape's body, in screen coordinates: what hovering means.
    private func hoverFrame() -> NSRect? {
        guard let geometry, let metrics = geometry.metrics, let kind = model.mode?.kind else { return nil }
        return geometry.screenRect(metrics.body(kind, expandedHeight: model.expandedHeight))
    }

    /// Moves the window and keeps the canvas where it was on screen, then retargets hovering.
    private func setWindowFrame(_ frame: NSRect) {
        guard let panel, let hosting, let geometry, let metrics = geometry.metrics else { return }
        let canvas = geometry.screenRect(metrics.canvas)
        panel.setFrame(frame, display: false)
        hosting.setFrameOrigin(NSPoint(x: canvas.minX - frame.minX, y: canvas.minY - frame.minY))
        if let hover = hoverFrame() {
            hosting.hoverRect = hosting.convert(panel.convertFromScreen(hover), from: nil)
        }
        // A tracking area added under a still mouse reports nothing, so check by hand.
        hoverChanged(isMouseInside)
    }

    private var isMouseInside: Bool {
        hoverFrame()?.contains(NSEvent.mouseLocation) ?? false
    }

    // MARK: Hover and keys

    /// Expands once the mouse has rested inside briefly, collapses a moment after it leaves
    /// (unless the panel has the keyboard), and cancels either if the mouse changes its mind.
    private func hoverChanged(_ inside: Bool) {
        if inside {
            guard !expanded else { return cancelHover() }
            guard hoverTask == nil else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: Self.expandDelay)
                guard let self, !Task.isCancelled else { return }
                self.hoverTask = nil
                if self.isMouseInside { self.expand() }
            }
        } else {
            cancelHover()
            guard expanded, panel?.isKeyWindow != true else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: Self.collapseDelay)
                guard let self, !Task.isCancelled else { return }
                self.hoverTask = nil
                if !self.isMouseInside { self.collapse() }
            }
        }
    }

    private func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    private func perform(_ action: PanelAction) {
        collapse()
        actions.perform(action)
    }

    func windowDidResignKey(_ notification: Notification) {
        if !isMouseInside { collapse() }
    }
}
