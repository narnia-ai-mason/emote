import AppKit
import Carbon.HIToolbox
import EmoteCore
import SwiftUI

struct HotkeyRecorder: View {
  @Binding var binding: HotkeyBinding
  @State private var isRecording = false
  @State private var monitor: Any?
  @State private var functionHeld = false

  var body: some View {
    HStack(spacing: 8) {
      Text(isRecording ? "Press a shortcut…" : binding.displayName)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(
              isRecording ? Color.accentColor : Color.primary.opacity(0.12),
              lineWidth: 1
            )
        )
        .onTapGesture {
          isRecording = true
        }

      Button(isRecording ? "Cancel" : "Change") {
        isRecording.toggle()
      }
    }
    .onChange(of: isRecording) { _, recording in
      if recording {
        startCapture()
      } else {
        stopCapture()
      }
    }
    .onDisappear {
      isRecording = false
      stopCapture()
    }
  }

  private func startCapture() {
    stopCapture()
    functionHeld = false
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
      if event.type == .flagsChanged {
        return handleFlagsChanged(event)
      }
      return handleKeyDown(event)
    }
  }

  private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
    guard event.keyCode == UInt16(kVK_Function) else {
      return nil
    }
    if event.modifierFlags.contains(.function) {
      functionHeld = true
    } else if functionHeld {
      functionHeld = false
      finish(
        HotkeyBinding(keyCode: UInt16(kVK_Function), modifiers: [.function])
      )
    }
    return nil
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    let extras = event.modifierFlags.intersection([.control, .option, .shift, .command, .function])
    if event.keyCode == UInt16(kVK_Escape), extras.isEmpty {
      DispatchQueue.main.async { isRecording = false }
      return nil
    }
    guard let recorded = HotkeyBinding(event: event) else {
      return nil
    }
    finish(recorded)
    return nil
  }

  private func finish(_ recorded: HotkeyBinding) {
    binding = recorded
    DispatchQueue.main.async { isRecording = false }
  }

  private func stopCapture() {
    functionHeld = false
    if let monitor {
      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }
  }
}

extension HotkeyBinding {
  init?(event: NSEvent) {
    let recorded = HotkeyBinding(
      keyCode: event.keyCode,
      modifiers: .from(event.modifierFlags)
    )
    guard recorded.hasRequiredModifiers else {
      return nil
    }
    self = recorded
  }

  func matches(_ event: CGEvent) -> Bool {
    let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let eventModifiers = Modifiers.from(event)
    if isFunctionKeyOnly {
      return event.type == .flagsChanged && eventModifiers == [.function]
    }
    return event.type == .keyDown && code == keyCode && eventModifiers == modifiers
  }
}

extension HotkeyBinding.Modifiers {
  static func from(_ flags: NSEvent.ModifierFlags) -> Self {
    var modifiers = Self()
    if flags.contains(.control) { modifiers.insert(.control) }
    if flags.contains(.option) { modifiers.insert(.option) }
    if flags.contains(.shift) { modifiers.insert(.shift) }
    if flags.contains(.command) { modifiers.insert(.command) }
    if flags.contains(.function) { modifiers.insert(.function) }
    return modifiers
  }

  static func from(_ event: CGEvent) -> Self {
    from(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
  }
}
