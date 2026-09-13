// Emote demo driver.
//
// Types a scripted scenario into the frontmost app, presses the Emote hotkey,
// waits for the HUD to show suggestions, and picks one. scripts/record-demo.sh
// runs this while screencapture records the window.
//
// Build and run:
//   swiftc -O -o .build/demo/driver scripts/demo/driver.swift
//   .build/demo/driver scripts/demo/scenario-ko.txt [--hotkey fn] [--cps 12]
//   .build/demo/driver --check      # permissions, Emote pid, HUD state
//   .build/demo/driver --screen     # "width height" of the main display in points
//   .build/demo/driver --input-source com.apple.keylayout.ABC
//                                   # select a keyboard layout; prints the previous one
//
// Scenario file: one command per line. A line starting with # is a comment.
//   type <text>      type text. \n = Return key, \s = space, \\ = backslash
//   key <combo>      press a key: cmd+left, shift+alt+left, shift+cmd+h, return
//   fn               press the Emote hotkey (fn, or --hotkey)
//   pick <emoji...>  wait for the HUD and choose the first listed emoji that it
//                    shows (Tab to it, then Return). When none is shown, press
//                    the hotkey again for a new set, twice at most, then take
//                    the first suggestion and mark the pick as a fallback.
//   pick <n>         wait for the HUD, press Tab n times, then Return
//   again            show the current suggestions, then press the hotkey for a
//                    new set; presses once more if the set did not change
//   peek             wait for the HUD, log what it shows, then press Escape
//   wait <ms>        pause
//   cps <n>          characters per second for `type` (default 12)
//   mouse <x> <y>    move the pointer (points, top-left origin)
//   click <x> <y>    click at a point
//   escape           press Escape
//
// The terminal app that runs this needs Accessibility permission. Typing sends
// Unicode characters directly, so select a Latin keyboard layout first (a Korean
// input mode would turn "Mason" into jamo); scripts/record-demo.sh does that
// with --input-source before recording and restores the previous layout after.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

struct Failure: Error {
  let message: String
}

let keyCodes: [String: CGKeyCode] = [
  "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
  "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
  "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
  "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "return": 36,
  "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
  "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "escape": 53,
  "fn": 63, "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119,
  "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
]

final class Driver {
  let source = CGEventSource(stateID: .hidSystemState)
  let emoteBundleID = "com.minsikseo.emote"
  let started = Date()
  var cps = 12.0
  var hotkey = "fn"
  var picksFailed = 0

  // MARK: Logging and timing

  func log(_ message: String) {
    let elapsed = Date().timeIntervalSince(started)
    print(String(format: "[%6.2fs] ", elapsed) + message)
    fflush(stdout)
  }

  func sleep(_ milliseconds: Double) {
    usleep(useconds_t(max(0, milliseconds) * 1000))
  }

  // MARK: Keyboard

  func press(_ combo: String) throws {
    let parts = combo.lowercased().split(separator: "+").map(String.init)
    guard let keyName = parts.last else {
      throw Failure(message: "empty key combo")
    }
    var flags: CGEventFlags = []
    for modifier in parts.dropLast() {
      switch modifier {
      case "cmd", "command": flags.insert(.maskCommand)
      case "shift": flags.insert(.maskShift)
      case "alt", "opt", "option": flags.insert(.maskAlternate)
      case "ctrl", "control": flags.insert(.maskControl)
      case "fn": flags.insert(.maskSecondaryFn)
      default: throw Failure(message: "unknown modifier: \(modifier)")
      }
    }
    guard let code = keyCodes[keyName] else {
      throw Failure(message: "unknown key: \(keyName)")
    }
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    else {
      throw Failure(message: "could not create key event")
    }
    // Press the modifiers one by one, like a real keyboard, and release them
    // afterwards. Without the release events the text input system keeps
    // believing the modifiers are held and drops the Unicode typing that follows.
    let modifierKeys = modifierSequence(for: flags)
    var held: CGEventFlags = []
    for (modifierCode, flag) in modifierKeys {
      held.insert(flag)
      postFlagsChanged(modifierCode, flags: held)
      sleep(12)
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    sleep(45)
    up.post(tap: .cghidEventTap)
    for (modifierCode, flag) in modifierKeys.reversed() {
      sleep(12)
      held.remove(flag)
      postFlagsChanged(modifierCode, flags: held)
    }
  }

  private func modifierSequence(for flags: CGEventFlags) -> [(CGKeyCode, CGEventFlags)] {
    var sequence: [(CGKeyCode, CGEventFlags)] = []
    if flags.contains(.maskControl) { sequence.append((CGKeyCode(kVK_Control), .maskControl)) }
    if flags.contains(.maskAlternate) { sequence.append((CGKeyCode(kVK_Option), .maskAlternate)) }
    if flags.contains(.maskShift) { sequence.append((CGKeyCode(kVK_Shift), .maskShift)) }
    if flags.contains(.maskCommand) { sequence.append((CGKeyCode(kVK_Command), .maskCommand)) }
    if flags.contains(.maskSecondaryFn) { sequence.append((CGKeyCode(kVK_Function), .maskSecondaryFn)) }
    return sequence
  }

  private func postFlagsChanged(_ code: CGKeyCode, flags: CGEventFlags) {
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: !flags.isEmpty) else {
      return
    }
    event.type = .flagsChanged
    event.flags = flags
    event.post(tap: .cghidEventTap)
  }

  func pressFunctionKey() {
    let code = CGKeyCode(kVK_Function)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    else {
      return
    }
    down.type = .flagsChanged
    down.flags = .maskSecondaryFn
    up.type = .flagsChanged
    up.flags = []
    down.post(tap: .cghidEventTap)
    sleep(90)
    up.post(tap: .cghidEventTap)
  }

  private var lastHotkeyPress: Date?
  var longestWait = 0.0

  func pressHotkey() throws {
    log("hotkey \(hotkey)")
    lastHotkeyPress = Date()
    if hotkey == "fn" {
      pressFunctionKey()
    } else {
      try press(hotkey)
    }
  }

  /// Seconds from the last hotkey press until now, logged and kept for the summary.
  private func noteWait() {
    guard let pressed = lastHotkeyPress else {
      return
    }
    let wait = Date().timeIntervalSince(pressed)
    longestWait = max(longestWait, wait)
    log(String(format: "HUD answered after %.1fs", wait))
  }

  func typeText(_ text: String) throws {
    for character in text {
      if character == "\n" {
        try press("return")
      } else {
        typeUnicode(String(character))
      }
      sleep(delay(after: character))
    }
  }

  private func delay(after character: Character) -> Double {
    let base = 1000.0 / cps
    var extra = 0.0
    switch character {
    case ".", "!", "?": extra = base * 3
    case ",": extra = base * 1.5
    case "\n": extra = base * 4
    case " ": extra = base * 0.3
    default: break
    }
    return base * Double.random(in: 0.65...1.35) + extra
  }

  private func typeUnicode(_ text: String) {
    let units = Array(text.utf16)
    guard !units.isEmpty,
      let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else {
      return
    }
    units.withUnsafeBufferPointer { buffer in
      guard let base = buffer.baseAddress else {
        return
      }
      down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
      up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }

  // MARK: Mouse

  func moveMouse(to point: CGPoint) {
    CGEvent(
      mouseEventSource: source, mouseType: .mouseMoved,
      mouseCursorPosition: point, mouseButton: .left
    )?.post(tap: .cghidEventTap)
  }

  func click(at point: CGPoint) {
    moveMouse(to: point)
    sleep(120)
    CGEvent(
      mouseEventSource: source, mouseType: .leftMouseDown,
      mouseCursorPosition: point, mouseButton: .left
    )?.post(tap: .cghidEventTap)
    sleep(60)
    CGEvent(
      mouseEventSource: source, mouseType: .leftMouseUp,
      mouseCursorPosition: point, mouseButton: .left
    )?.post(tap: .cghidEventTap)
  }

  // MARK: Input source

  /// Selects the enabled input source with this ID and returns the ID of the
  /// one that was current, or nil when the requested source is not enabled.
  func selectInputSource(id: String) -> String? {
    let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let currentID = inputSourceID(current)
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
      (list as NSArray).count > 0
    else {
      return nil
    }
    let target = (list as NSArray)[0] as! TISInputSource
    TISSelectInputSource(target)
    sleep(250)
    return currentID
  }

  private func inputSourceID(_ source: TISInputSource) -> String {
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
      return ""
    }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
  }

  // MARK: Emote HUD

  enum HUDState {
    case hidden
    case loading
    case results([String])
    case message(String)
  }

  func emotePID() -> pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: emoteBundleID)
      .first?.processIdentifier
  }

  func hudState() -> HUDState {
    guard let pid = emotePID() else {
      return .hidden
    }
    let app = AXUIElementCreateApplication(pid)
    guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement],
      !windows.isEmpty
    else {
      return .hidden
    }
    var buttons: [String] = []
    var texts: [String] = []
    var loading = false
    for window in windows {
      walk(window, depth: 0) { element, role in
        switch role {
        case "AXButton":
          let title = (attribute(element, kAXTitleAttribute) as? String)
            ?? (attribute(element, kAXDescriptionAttribute) as? String)
            ?? firstStaticText(in: element)
            ?? ""
          buttons.append(title)
        case "AXStaticText":
          if let value = attribute(element, kAXValueAttribute) as? String {
            texts.append(value)
          }
        case "AXProgressIndicator":
          loading = true
        default:
          break
        }
      }
    }
    if !buttons.isEmpty {
      return .results(buttons)
    }
    if loading || texts.contains(where: { $0.hasPrefix("Finding") }) {
      return .loading
    }
    if let message = texts.first(where: { !$0.isEmpty }) {
      return .message(message)
    }
    return .loading
  }

  private func walk(_ element: AXUIElement, depth: Int, visit: (AXUIElement, String) -> Void) {
    guard depth < 16 else {
      return
    }
    let role = attribute(element, kAXRoleAttribute) as? String ?? ""
    visit(element, role)
    guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
      return
    }
    for child in children {
      walk(child, depth: depth + 1, visit: visit)
    }
  }

  private func firstStaticText(in element: AXUIElement) -> String? {
    var found: String?
    walk(element, depth: 0) { child, role in
      if found == nil, role == "AXStaticText",
        let value = attribute(child, kAXValueAttribute) as? String
      {
        found = value
      }
    }
    return found
  }

  private func attribute(_ element: AXUIElement, _ name: String) -> Any? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard result == .success else {
      return nil
    }
    return value
  }

  func describe(_ state: HUDState) -> String {
    switch state {
    case .hidden: return "hidden"
    case .loading: return "loading"
    case .results(let emojis): return "results \(emojis)"
    case .message(let message): return "message \"\(message)\""
    }
  }

  enum Choice {
    case index(Int)
    case prefer([String])
  }

  struct PickRecord {
    var shown: [String]
    var chosen: String
    var fallback: Bool
  }

  var pickRecords: [PickRecord] = []
  var fallbackPicks: Int { pickRecords.filter(\.fallback).count }

  /// Emoji comparison ignores variation selectors, so ❤️ and ❤ match.
  private func normalized(_ emoji: String) -> String {
    String(String.UnicodeScalarView(emoji.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0xFE0E }))
  }

  /// Waits until the HUD shows suggestions or a message. With `afterPress`,
  /// first waits for the previous list to go away so it is not read twice.
  func waitForHUD(afterPress: Bool) -> HUDState {
    if afterPress {
      let settle = Date().addingTimeInterval(1.2)
      while Date() < settle {
        if case .results = hudState() {
          sleep(30)
        } else {
          break
        }
      }
    }
    var state = hudState()
    let appearDeadline = Date().addingTimeInterval(4)
    while case .hidden = state, Date() < appearDeadline {
      sleep(50)
      state = hudState()
    }
    let resultDeadline = Date().addingTimeInterval(25)
    while Date() < resultDeadline {
      state = hudState()
      if case .loading = state {
        sleep(80)
        continue
      }
      break
    }
    noteWait()
    return state
  }

  func pick(_ choice: Choice) throws {
    var attempt = 0
    var afterPress = false
    while true {
      attempt += 1
      let state = waitForHUD(afterPress: afterPress)
      switch state {
      case .results(let emojis):
        var index = 0
        var fallback = false
        switch choice {
        case .index(let n):
          index = emojis.isEmpty ? 0 : n % emojis.count
        case .prefer(let preferred):
          let shown = emojis.map(normalized)
          var found: Int?
          for candidate in preferred {
            if let at = shown.firstIndex(of: normalized(candidate)) {
              found = at
              break
            }
          }
          if let found {
            index = found
          } else if attempt < 3 {
            log("pick: none of \(preferred) in \(emojis); asking again (attempt \(attempt))")
            sleep(700)
            try pressHotkey()
            afterPress = true
            continue
          } else {
            log("pick: none of \(preferred) in \(emojis); taking the first")
            fallback = true
          }
        }
        log("pick: HUD \(emojis), tab x\(index)")
        sleep(650)
        for _ in 0..<index {
          try press("tab")
          sleep(380)
        }
        try press("return")
        let chosen = emojis.isEmpty ? "?" : emojis[index]
        pickRecords.append(PickRecord(shown: emojis, chosen: chosen, fallback: fallback))
        log("pick: chose \(chosen)\(fallback ? " (fallback)" : "")")
        sleep(450)
        return
      case .message(let message):
        log("pick: HUD message \"\(message)\" (attempt \(attempt))")
        try press("escape")
      case .hidden:
        log("pick: HUD did not appear (attempt \(attempt))")
      case .loading:
        log("pick: timed out waiting for results (attempt \(attempt))")
        try press("escape")
      }
      if attempt < 3 {
        sleep(800)
        try pressHotkey()
        afterPress = true
        continue
      }
      picksFailed += 1
      return
    }
  }

  /// Lets the viewer see the current suggestions, then presses the hotkey for
  /// a new set. Presses once more when the set did not change.
  func again() throws {
    guard case .results(let first) = waitForHUD(afterPress: false) else {
      log("again: no suggestions to replace; leaving it to the next pick")
      return
    }
    log("again: first set \(first)")
    var previous = first
    for attempt in 1...3 {
      sleep(900)
      try pressHotkey()
      guard case .results(let next) = waitForHUD(afterPress: true) else {
        log("again: no new suggestions; leaving it to the next pick")
        return
      }
      if next != previous {
        log("again: new set \(next)")
        return
      }
      log("again: same set \(next) (attempt \(attempt))")
      previous = next
    }
  }

  // MARK: Scenario

  func run(scenario path: String) throws {
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    let lines = contents.components(separatedBy: "\n")
    for (number, rawLine) in lines.enumerated() {
      let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") {
        continue
      }
      let command: String
      let argument: String
      if let space = line.firstIndex(of: " ") {
        command = String(line[..<space])
        argument = String(line[line.index(after: space)...])
      } else {
        command = trimmed
        argument = ""
      }
      do {
        try execute(command: command, argument: argument)
      } catch let failure as Failure {
        throw Failure(message: "line \(number + 1): \(failure.message)")
      }
    }
  }

  private func execute(command: String, argument: String) throws {
    switch command {
    case "type":
      let text = unescape(argument)
      log("type \(text.replacingOccurrences(of: "\n", with: "⏎"))")
      try typeText(text)
    case "key":
      log("key \(argument)")
      try press(argument.trimmingCharacters(in: .whitespaces))
    case "fn":
      try pressHotkey()
    case "pick":
      let spec = argument.trimmingCharacters(in: .whitespaces)
      if let n = Int(spec) {
        try pick(.index(n))
      } else {
        let preferred = spec.split(separator: " ").map(String.init)
        guard !preferred.isEmpty else {
          throw Failure(message: "pick needs an index or a list of emojis")
        }
        try pick(.prefer(preferred))
      }
    case "again":
      try again()
    case "peek":
      let state = waitForHUD(afterPress: false)
      log("peek: \(describe(state))")
      try press("escape")
      sleep(400)
    case "wait":
      guard let ms = Double(argument.trimmingCharacters(in: .whitespaces)) else {
        throw Failure(message: "wait needs milliseconds")
      }
      sleep(ms)
    case "cps":
      guard let value = Double(argument.trimmingCharacters(in: .whitespaces)), value > 0 else {
        throw Failure(message: "cps needs a positive number")
      }
      cps = value
    case "mouse", "click":
      let parts = argument.split(separator: " ").compactMap { Double($0) }
      guard parts.count == 2 else {
        throw Failure(message: "\(command) needs x y")
      }
      let point = CGPoint(x: parts[0], y: parts[1])
      if command == "click" {
        log("click \(Int(point.x)),\(Int(point.y))")
        click(at: point)
      } else {
        moveMouse(to: point)
      }
    case "escape":
      try press("escape")
    default:
      throw Failure(message: "unknown command: \(command)")
    }
  }

  private func unescape(_ text: String) -> String {
    var result = ""
    var iterator = text.makeIterator()
    while let character = iterator.next() {
      guard character == "\\" else {
        result.append(character)
        continue
      }
      switch iterator.next() {
      case "n": result.append("\n")
      case "s": result.append(" ")
      case "\\": result.append("\\")
      case let other?: result.append("\\"); result.append(other)
      case nil: result.append("\\")
      }
    }
    return result
  }
}

// MARK: - Entry point

let driver = Driver()
var scenarioPath: String?
var arguments = Array(CommandLine.arguments.dropFirst())
var checkOnly = false

while !arguments.isEmpty {
  let argument = arguments.removeFirst()
  switch argument {
  case "--hotkey":
    driver.hotkey = arguments.isEmpty ? "fn" : arguments.removeFirst()
  case "--cps":
    driver.cps = Double(arguments.isEmpty ? "12" : arguments.removeFirst()) ?? 12
  case "--check":
    checkOnly = true
  case "--screen":
    let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
    let size = screen?.frame.size ?? .zero
    print("\(Int(size.width)) \(Int(size.height))")
    exit(0)
  case "--input-source":
    guard !arguments.isEmpty, let previous = driver.selectInputSource(id: arguments.removeFirst())
    else {
      print("input source not enabled")
      exit(2)
    }
    print(previous)
    exit(0)
  default:
    scenarioPath = argument
  }
}

let trusted = AXIsProcessTrusted()
let emotePID = driver.emotePID()

if checkOnly {
  print("accessibility: \(trusted)")
  print("screen recording: \(CGPreflightScreenCaptureAccess())")
  print("emote pid: \(emotePID.map(String.init) ?? "not running")")
  print("hud: \(driver.describe(driver.hudState()))")
  exit(trusted && emotePID != nil ? 0 : 2)
}

guard trusted else {
  print("Accessibility permission is missing for the app running this driver.")
  print("System Settings → Privacy & Security → Accessibility")
  exit(2)
}
guard emotePID != nil else {
  print("Emote is not running.")
  exit(2)
}
guard let scenarioPath else {
  print("usage: driver <scenario.txt> [--hotkey fn] [--cps 12]")
  exit(2)
}

do {
  try driver.run(scenario: scenarioPath)
} catch let failure as Failure {
  driver.log("error: \(failure.message)")
  exit(1)
}
driver.log(String(
  format: "done, failed picks: %d, fallback picks: %d, longest wait: %.1fs",
  driver.picksFailed, driver.fallbackPicks, driver.longestWait
))
for (number, record) in driver.pickRecords.enumerated() {
  let mark = record.fallback ? " (fallback)" : ""
  print("  \(number + 1). \(record.chosen)\(mark)  from \(record.shown.joined(separator: " "))")
}
if driver.picksFailed > 0 {
  exit(3)
}
exit(driver.fallbackPicks > 0 ? 4 : 0)
