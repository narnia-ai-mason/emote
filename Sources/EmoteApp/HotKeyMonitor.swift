import AppKit
import Carbon
import EmoteCore
import Foundation

@MainActor
final class HotKeyMonitor {
  static let shared = HotKeyMonitor()

  enum HUDKey {
    case escape
    case next
    case previous
    case commit
  }

  var onRecommend: (() -> Void)?
  var onHUD: ((HUDKey) -> Void)?

  private var recommendRef: EventHotKeyRef?
  private var recommendTap: RecommendEventTap?
  private var hudRefs: [EventHotKeyRef] = []
  private var handlerInstalled = false

  func register(_ binding: HotkeyBinding = .default) {
    installHandlerIfNeeded()
    unregisterRecommend()
    if binding.usesEventTap {
      let tap = RecommendEventTap()
      tap.binding = binding
      tap.onMatch = { [weak self] in
        self?.onRecommend?()
      }
      if tap.start() {
        recommendTap = tap
        return
      }
    }
    recommendRef = registerKey(UInt32(binding.keyCode), binding.carbonModifiers, id: 1)
  }

  private func unregisterRecommend() {
    if let recommendRef {
      UnregisterEventHotKey(recommendRef)
      self.recommendRef = nil
    }
    recommendTap?.stop()
    recommendTap = nil
  }

  func registerHUD() {
    installHandlerIfNeeded()
    unregisterHUD()
    hudRefs = [
      registerKey(UInt32(kVK_Escape), 0, id: 10),
      registerKey(UInt32(kVK_Tab), 0, id: 11),
      registerKey(UInt32(kVK_Tab), UInt32(shiftKey), id: 12),
      registerKey(UInt32(kVK_LeftArrow), 0, id: 13),
      registerKey(UInt32(kVK_RightArrow), 0, id: 14),
      registerKey(UInt32(kVK_Return), 0, id: 15),
      registerKey(UInt32(kVK_ANSI_KeypadEnter), 0, id: 16),
    ].compactMap { $0 }
  }

  func unregisterHUD() {
    for ref in hudRefs {
      UnregisterEventHotKey(ref)
    }
    hudRefs = []
  }

  private func installHandlerIfNeeded() {
    guard !handlerInstalled else {
      return
    }
    handlerInstalled = true
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        guard status == noErr else {
          return noErr
        }
        DispatchQueue.main.async {
          HotKeyMonitor.shared.dispatch(hotKeyID)
        }
        return noErr
      },
      1,
      &eventType,
      nil,
      nil
    )
  }

  private func dispatch(_ hotKeyID: EventHotKeyID) {
    switch hotKeyID.id {
    case 1:
      onRecommend?()
    case 10:
      onHUD?(.escape)
    case 11, 14:
      onHUD?(.next)
    case 12, 13:
      onHUD?(.previous)
    case 15, 16:
      onHUD?(.commit)
    default:
      break
    }
  }

  private func registerKey(_ key: UInt32, _ modifiers: UInt32, id: UInt32) -> EventHotKeyRef? {
    var ref: EventHotKeyRef?
    let identifier = EventHotKeyID(signature: 0x454D_4F54, id: id)
    RegisterEventHotKey(key, modifiers, identifier, GetApplicationEventTarget(), 0, &ref)
    return ref
  }
}

private final class RecommendEventTap: @unchecked Sendable {
  var binding = HotkeyBinding.default
  var onMatch: (() -> Void)?

  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  @discardableResult
  func start() -> Bool {
    stop()
    let mask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(mask),
        callback: { _, type, event, refcon in
          guard let refcon else {
            return Unmanaged.passUnretained(event)
          }
          let monitor = Unmanaged<RecommendEventTap>.fromOpaque(refcon).takeUnretainedValue()
          return monitor.handle(type: type, event: event)
        },
        userInfo: context
      )
    else {
      return false
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.tap = tap
    self.source = source
    return true
  }

  func stop() {
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
      self.tap = nil
    }
    if let source {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      CFRunLoopSourceInvalidate(source)
      self.source = nil
    }
  }

  private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }
    guard binding.matches(event) else {
      return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.keyboardEventAutorepeat) == 1 {
      return nil
    }
    DispatchQueue.main.async { [onMatch] in
      onMatch?()
    }
    return nil
  }

  deinit {
    stop()
  }
}
