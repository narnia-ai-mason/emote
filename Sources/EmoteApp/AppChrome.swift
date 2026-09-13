import AppKit

@MainActor
enum AppChrome {
  static var openSettingsWindow: (() -> Void)?
  static var openAboutWindow: (() -> Void)?

  static func becomeRegularApp() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  static func showSettings() {
    becomeRegularApp()
    openSettingsWindow?()
  }

  static func showAbout() {
    becomeRegularApp()
    openAboutWindow?()
  }

  static func openAppleIntelligenceSettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.settings.AppleIntelligenceAndSiri",
      "x-apple.systempreferences:com.apple.Siri-Settings.extension",
      "x-apple.systempreferences:com.apple.Siri-Settings",
    ]
    for raw in candidates {
      if let url = URL(string: raw), NSWorkspace.shared.open(url) {
        return
      }
    }
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
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
