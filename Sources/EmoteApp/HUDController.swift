import AppKit
import EmoteCore
import SwiftUI

@MainActor
final class HUDController: NSObject {
  var onDismiss: (() -> Void)?

  private var panel: NSPanel?
  private var localMonitor: Any?
  private var globalMonitor: Any?
  private var selectedIndex = 0
  private var recommendations: [EmojiRecommendation] = []
  private var onCommit: ((EmojiRecommendation) -> Void)?
  private var anchor: CGRect?

  func showLoading(anchor: CGRect?) {
    selectedIndex = 0
    recommendations = []
    onCommit = nil
    self.anchor = anchor
    present(
      HUDView(
        recommendations: [],
        selectedIndex: 0,
        isLoading: true,
        message: nil,
        onChoose: { _ in }
      ),
      anchor: anchor
    )
  }

  func show(
    recommendations: [EmojiRecommendation],
    anchor: CGRect?,
    onCommit: @escaping (EmojiRecommendation) -> Void
  ) {
    selectedIndex = 0
    self.recommendations = recommendations
    self.onCommit = onCommit
    self.anchor = anchor
    render()
  }

  func show(message: String, anchor: CGRect?) {
    recommendations = []
    onCommit = nil
    self.anchor = anchor
    present(
      HUDView(
        recommendations: [],
        selectedIndex: 0,
        isLoading: false,
        message: message,
        onChoose: { _ in }
      ),
      anchor: anchor
    )
  }

  func hide() {
    let dismiss = onDismiss
    HotKeyMonitor.shared.unregisterHUD()
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor)
      self.globalMonitor = nil
    }
    panel?.orderOut(nil)
    panel = nil
    onCommit = nil
    recommendations = []
    dismiss?()
  }

  func handle(_ key: HotKeyMonitor.HUDKey) {
    switch key {
    case .escape:
      hide()
    case .next:
      move(1)
    case .previous:
      move(-1)
    case .commit:
      guard !recommendations.isEmpty else {
        return
      }
      choose(selectedIndex)
    }
  }

  private func render() {
    present(
      HUDView(
        recommendations: recommendations,
        selectedIndex: selectedIndex,
        isLoading: false,
        message: nil,
        onChoose: { [weak self] index in
          self?.choose(index)
        }
      ),
      anchor: anchor
    )
  }

  private func present(_ view: HUDView, anchor: CGRect?) {
    let host = NSHostingView(rootView: view)
    host.sizingOptions = [.intrinsicContentSize]
    host.frame.size = host.fittingSize

    let panel = self.panel ?? makePanel()
    panel.contentView = host
    panel.setContentSize(host.fittingSize)
    panel.setFrameOrigin(origin(for: panel.frame.size, anchor: anchor))
    panel.orderFrontRegardless()
    self.panel = panel
    HotKeyMonitor.shared.registerHUD()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      guard let self, self.panel != nil else {
        return
      }
      self.installMonitorIfNeeded()
    }
  }

  private func makePanel() -> NSPanel {
    let panel = KeyPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle,
    ]
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    return panel
  }

  private func origin(for size: CGSize, anchor: CGRect?) -> NSPoint {
    let point = anchor?.origin
    let screen = point.flatMap { candidate in
      NSScreen.screens.first { NSMouseInRect(candidate, $0.frame, false) }
    } ?? NSScreen.main ?? NSScreen.screens.first
    let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
    let origin = HUDPlacement.origin(
      size: size,
      anchor: anchor,
      visible: visible
    )
    return NSPoint(x: origin.x, y: origin.y)
  }

  private func installMonitorIfNeeded() {
    guard localMonitor == nil else {
      return
    }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else {
        return event
      }
      return self.handle(event) ? nil : event
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
      guard let self, let panel = self.panel else {
        return
      }
      let location = NSEvent.mouseLocation
      if !panel.frame.contains(location) {
        DispatchQueue.main.async {
          self.hide()
        }
      }
    }
  }

  private func handle(_ event: NSEvent) -> Bool {
    if event.keyCode == 53 {
      hide()
      return true
    }
    guard !recommendations.isEmpty else {
      return event.keyCode == 36
    }
    switch event.keyCode {
    case 48:
      move(event.modifierFlags.contains(.shift) ? -1 : 1)
      return true
    case 123:
      move(-1)
      return true
    case 124:
      move(1)
      return true
    case 36, 76:
      choose(selectedIndex)
      return true
    default:
      return false
    }
  }

  private func move(_ delta: Int) {
    guard !recommendations.isEmpty else {
      return
    }
    selectedIndex = (selectedIndex + delta + recommendations.count) % recommendations.count
    render()
  }

  private func choose(_ index: Int) {
    guard recommendations.indices.contains(index) else {
      return
    }
    let recommendation = recommendations[index]
    let commit = onCommit
    hide()
    commit?(recommendation)
  }
}

private final class KeyPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
