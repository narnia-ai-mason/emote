import AppKit

@MainActor
enum AppChrome {
  static var openSettingsWindow: (() -> Void)?

  static func becomeRegularApp() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  static func showSettings() {
    becomeRegularApp()
    openSettingsWindow?()
  }

  static func resignToMenuBarIfNeeded() {
    let hasMainWindow = NSApp.windows.contains { window in
      window.isVisible && window.canBecomeMain
    }
    guard !hasMainWindow else {
      return
    }
    NSApp.setActivationPolicy(.accessory)
  }
}
