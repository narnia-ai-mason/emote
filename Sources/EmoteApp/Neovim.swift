import AppKit
import Darwin
import EmoteCore
import Foundation

/// Neovim running in a terminal. The terminal only shows a picture of the buffer, with line numbers
/// and wrapped lines, and never the Visual selection. Neovim's own RPC socket gives the buffer,
/// cursor, and mode, and takes the emoji without going through completion plugins.
enum Neovim {
  struct Target: Sendable {
    var socket: String
    var state: NeovimState
  }

  private struct Instance: Sendable {
    var socket: String
    var pid: pid_t
  }

  private static let terminals: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "net.kovidgoyal.kitty",
    "com.mitchellh.ghostty",
    "io.appmakes.otty",
    "dev.warp.Warp-Stable",
    "org.alacritty",
    "io.alacritty",
    "com.github.wez.wezterm",
    "co.zeit.hyper",
    "com.neovide.neovide",
  ]

  static func isTerminal(_ app: NSRunningApplication) -> Bool {
    guard let identifier = app.bundleIdentifier else { return false }
    return terminals.contains(identifier) || identifier.lowercased().contains("term")
  }

  /// The instance the person is typing in inside `app`. `screen` is the terminal's text, when its
  /// accessibility shares it, to tell visible instances from ones in other tabs.
  static func target(in app: NSRunningApplication, screen: String?) -> Target? {
    guard isTerminal(app) else { return nil }
    let all = instances()
    var candidates = all.filter { runs(under: app, pid: $0.pid) }
    if candidates.isEmpty {
      candidates = all.filter { ancestors(of: $0.pid).contains { executableName($0) == "tmux" } }
    }
    guard !candidates.isEmpty else { return nil }

    let states = UnsafeStates(count: candidates.count)
    DispatchQueue.concurrentPerform(iterations: candidates.count) { index in
      states.set(index, readState(candidates[index].socket))
    }
    var targets = zip(candidates, states.values).compactMap { instance, state in
      state.map { Target(socket: instance.socket, state: $0) }
    }
    targets.removeAll { $0.state.focused == false }
    if targets.contains(where: { $0.state.focused == true }) {
      targets.removeAll { $0.state.focused != true }
    }
    if let screen, !screen.isEmpty {
      targets.removeAll { !isShown($0.state, on: screen) }
    }
    return targets.max { ($0.state.seen ?? 0) < ($1.state.seen ?? 0) }
  }

  /// Replace `range` of the target's text with `emoji`. False when the buffer changed since it was read.
  static func insert(_ emoji: String, replacing range: Range<Int>, in target: Target) -> Bool {
    let state = target.state
    let start = state.position(ofUTF16: range.lowerBound)
    let end = state.position(ofUTF16: range.upperBound)
    let arguments: [MessagePack] = [
      .int(Int64(state.buffer)), .int(Int64(state.tick)),
      .int(Int64(start.line)), .int(Int64(start.byte)),
      .int(Int64(end.line)), .int(Int64(end.byte)),
      .string(emoji),
    ]
    let connection = RPCConnection(path: target.socket)
    return connection?.call("nvim_exec_lua", [.string(insertScript), .array(arguments)])?.bool == true
  }

  /// Hooks every running instance early, so its focus and activity are known by the first recommendation.
  static func hookAll() {
    DispatchQueue.global(qos: .utility).async {
      for instance in instances() where hooked.insert(instance.socket) {
        _ = RPCConnection(path: instance.socket)?.call("nvim_exec_lua", [.string(hookScript), .array([])])
      }
    }
  }

  private static let hooked = SocketSet()

  private static func readState(_ socket: String) -> NeovimState? {
    guard let connection = RPCConnection(path: socket),
      connection.call("nvim_get_mode", [])?["blocking"]?.bool == false
    else { return nil }
    guard let json = connection.call("nvim_exec_lua", [.string(hookScript + stateScript), .array([])])?.string,
      let data = json.data(using: .utf8)
    else { return nil }
    hooked.insert(socket)
    return try? JSONDecoder().decode(NeovimState.self, from: data)
  }

  private static func isShown(_ state: NeovimState, on screen: String) -> Bool {
    let cursor = state.line - state.first
    let nearby = [cursor, cursor - 1, cursor + 1]
      .filter { state.lines.indices.contains($0) }
      .map { String(state.lines[$0].trimmingCharacters(in: .whitespaces).prefix(12)) }
      .filter { $0.count >= 4 }
    guard !nearby.isEmpty else { return true }
    return nearby.contains { screen.contains($0) }
  }

  // MARK: Processes

  private static func instances() -> [Instance] {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nvim.\(NSUserName())")
    let manager = FileManager.default
    guard let sessions = try? manager.contentsOfDirectory(atPath: root.path) else { return [] }
    return sessions.flatMap { session -> [Instance] in
      let folder = root.appendingPathComponent(session)
      let names = (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
      return names.compactMap { name in
        let parts = name.split(separator: ".")
        guard parts.count >= 2, parts[0] == "nvim", let pid = pid_t(parts[1]), kill(pid, 0) == 0 else { return nil }
        return Instance(socket: folder.appendingPathComponent(name).path, pid: pid)
      }
    }
  }

  /// iTerm2 runs shells under its own server process, which lives in the app bundle but not under the app.
  private static func runs(under app: NSRunningApplication, pid: pid_t) -> Bool {
    let bundle = app.bundleURL?.path
    return ancestors(of: pid).contains { ancestor in
      ancestor == app.processIdentifier
        || (bundle.map { executablePath(ancestor)?.hasPrefix($0 + "/") ?? false } ?? false)
    }
  }

  private static func ancestors(of pid: pid_t) -> [pid_t] {
    var chain: [pid_t] = []
    var current = pid
    for _ in 0..<32 {
      guard let parent = parentPID(current), parent > 1 else { break }
      chain.append(parent)
      current = parent
    }
    return chain
  }

  private static func parentPID(_ pid: pid_t) -> pid_t? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    return info.kp_eproc.e_ppid
  }

  private static func executablePath(_ pid: pid_t) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
    return String(cString: buffer)
  }

  private static func executableName(_ pid: pid_t) -> String? {
    executablePath(pid).map { URL(fileURLWithPath: $0).lastPathComponent }
  }

  // MARK: Lua

  private static let hookScript = """
    if not vim.g.emote_hooked then
      vim.g.emote_hooked = true
      local group = vim.api.nvim_create_augroup('emote', { clear = true })
      local clock = vim.uv or vim.loop
      local function now() local s, us = clock.gettimeofday(); return s + us / 1e6 end
      vim.api.nvim_create_autocmd('FocusGained', { group = group, callback = function()
        vim.g.emote_focused = true
        vim.g.emote_seen = now()
      end })
      vim.api.nvim_create_autocmd('FocusLost', { group = group, callback = function()
        vim.g.emote_focused = false
      end })
      vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'TextChanged', 'TextChangedI', 'ModeChanged' }, {
        group = group, callback = function() vim.g.emote_seen = now() end,
      })
    end

    """

  private static let stateScript = """
    local api = vim.api
    local cursor = api.nvim_win_get_cursor(0)
    local row = cursor[1]
    local first = math.max(1, row - 300)
    local last = math.min(api.nvim_buf_line_count(0), row + 300)
    local mode = api.nvim_get_mode()
    local v = vim.fn.getpos('v')
    local win = vim.fn.win_screenpos(0)
    return vim.json.encode({
      mode = mode.mode, blocking = mode.blocking,
      buffer = api.nvim_get_current_buf(), tick = vim.b.changedtick,
      editable = vim.bo.modifiable and vim.bo.buftype == '',
      first = first, lines = api.nvim_buf_get_lines(0, first - 1, last, false),
      line = row, col = cursor[2], vline = v[2], vcol = math.max(v[3] - 1, 0),
      rows = vim.o.lines, columns = vim.o.columns,
      screenRow = win[1] + vim.fn.winline() - 1, screenCol = win[2] + vim.fn.wincol() - 1,
      seen = vim.g.emote_seen, focused = vim.g.emote_focused,
    })
    """

  private static let insertScript = """
    local buffer, tick, r0, c0, r1, c1, emoji = ...
    local api = vim.api
    if api.nvim_get_current_buf() ~= buffer or vim.b[buffer].changedtick ~= tick then return false end
    local mode = api.nvim_get_mode().mode:sub(1, 1)
    if mode == 'v' or mode == 'V' or mode == '\\22' then
      api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
      mode = 'n'
    end
    api.nvim_buf_set_text(buffer, r0 - 1, c0, r1 - 1, c1, { emoji })
    local typing = mode == 'i' or mode == 'R'
    api.nvim_win_set_cursor(0, { r0, typing and c0 + #emoji or c0 })
    return true
    """
}

private final class UnsafeStates: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [NeovimState?]

  init(count: Int) { storage = Array(repeating: nil, count: count) }

  func set(_ index: Int, _ state: NeovimState?) {
    lock.lock()
    storage[index] = state
    lock.unlock()
  }

  var values: [NeovimState?] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

private final class SocketSet: @unchecked Sendable {
  private let lock = NSLock()
  private var sockets: Set<String> = []

  @discardableResult
  func insert(_ socket: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return sockets.insert(socket).inserted
  }
}

/// One blocking MessagePack-RPC connection to a Neovim socket. A busy or hung instance times out.
private final class RPCConnection {
  private let descriptor: Int32
  private var nextID: Int64 = 1
  private var buffer: [UInt8] = []

  init?(path: String, timeout: TimeInterval = 0.4) {
    let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard socket >= 0 else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count < capacity else {
      close(socket)
      return nil
    }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
      raw.copyBytes(from: pathBytes)
      raw[pathBytes.count] = 0
    }
    var time = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
    setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size))
    var noSignal: Int32 = 1
    setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else {
      close(socket)
      return nil
    }
    descriptor = socket
  }

  deinit { close(descriptor) }

  /// The call's result, or nil on an error reply or timeout.
  func call(_ method: String, _ parameters: [MessagePack]) -> MessagePack? {
    let id = nextID
    nextID += 1
    let request = MessagePack.array([.int(0), .int(id), .string(method), .array(parameters)]).encoded()
    let sent = request.withUnsafeBytes { send(descriptor, $0.baseAddress, $0.count, 0) }
    guard sent == request.count else { return nil }

    var chunk = [UInt8](repeating: 0, count: 65_536)
    while true {
      while let (message, length) = (try? MessagePack.decode(buffer)) ?? nil {
        buffer.removeFirst(length)
        guard let parts = message.array, parts.count == 4, parts[0].int == 1, parts[1].int == id else { continue }
        return parts[2].isNull ? parts[3] : nil
      }
      let count = recv(descriptor, &chunk, chunk.count, 0)
      guard count > 0 else { return nil }
      buffer.append(contentsOf: chunk[0..<count])
    }
  }
}
