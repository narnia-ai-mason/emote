import Foundation

/// The subset of MessagePack that Neovim's RPC speaks.
public indirect enum MessagePack: Sendable {
  case null
  case bool(Bool)
  case int(Int64)
  case double(Double)
  case string(String)
  case binary([UInt8])
  case array([MessagePack])
  case map([(key: MessagePack, value: MessagePack)])
  /// Neovim sends buffer, window, and tabpage handles as extension types.
  case ext(Int8, [UInt8])

  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  public var array: [MessagePack]? {
    if case .array(let value) = self { return value }
    return nil
  }

  public var bool: Bool? {
    if case .bool(let value) = self { return value }
    return nil
  }

  public subscript(key: String) -> MessagePack? {
    guard case .map(let pairs) = self else { return nil }
    return pairs.first { $0.key.string == key }?.value
  }

  public var int: Int64? {
    if case .int(let value) = self { return value }
    return nil
  }

  public var isNull: Bool {
    if case .null = self { return true }
    return false
  }

  public func encoded() -> [UInt8] {
    var bytes: [UInt8] = []
    encode(into: &bytes)
    return bytes
  }

  private func encode(into bytes: inout [UInt8]) {
    switch self {
    case .null:
      bytes.append(0xC0)
    case .bool(let value):
      bytes.append(value ? 0xC3 : 0xC2)
    case .int(let value):
      if value >= 0, value < 0x80 {
        bytes.append(UInt8(value))
      } else if value < 0, value >= -32 {
        bytes.append(UInt8(bitPattern: Int8(value)))
      } else {
        bytes.append(0xD3)
        bytes.append(contentsOf: bigEndian(UInt64(bitPattern: value), count: 8))
      }
    case .double(let value):
      bytes.append(0xCB)
      bytes.append(contentsOf: bigEndian(value.bitPattern, count: 8))
    case .string(let value):
      let utf8 = Array(value.utf8)
      Self.header(&bytes, count: utf8.count, fix: 0xA0, fixLimit: 32, sizes: [0xD9, 0xDA, 0xDB])
      bytes.append(contentsOf: utf8)
    case .binary(let value):
      Self.header(&bytes, count: value.count, fix: nil, fixLimit: 0, sizes: [0xC4, 0xC5, 0xC6])
      bytes.append(contentsOf: value)
    case .array(let values):
      Self.header(&bytes, count: values.count, fix: 0x90, fixLimit: 16, sizes: [nil, 0xDC, 0xDD])
      for value in values { value.encode(into: &bytes) }
    case .map(let pairs):
      Self.header(&bytes, count: pairs.count, fix: 0x80, fixLimit: 16, sizes: [nil, 0xDE, 0xDF])
      for pair in pairs {
        pair.key.encode(into: &bytes)
        pair.value.encode(into: &bytes)
      }
    case .ext(let type, let data):
      bytes.append(0xC7)
      bytes.append(UInt8(data.count))
      bytes.append(UInt8(bitPattern: type))
      bytes.append(contentsOf: data)
    }
  }

  /// `sizes` holds the 8-, 16-, and 32-bit length markers; nil where the format has none.
  private static func header(_ bytes: inout [UInt8], count: Int, fix: UInt8?, fixLimit: Int, sizes: [UInt8?]) {
    if let fix, count < fixLimit {
      bytes.append(fix | UInt8(count))
    } else if let marker = sizes[0], count <= 0xFF {
      bytes.append(marker)
      bytes.append(UInt8(count))
    } else if let marker = sizes[1], count <= 0xFFFF {
      bytes.append(marker)
      bytes.append(contentsOf: bigEndian(UInt64(count), count: 2))
    } else if let marker = sizes[2] {
      bytes.append(marker)
      bytes.append(contentsOf: bigEndian(UInt64(count), count: 4))
    }
  }

  /// One value from the start of `bytes` and how many bytes it took; nil until enough bytes arrive.
  public static func decode(_ bytes: [UInt8]) throws -> (value: MessagePack, length: Int)? {
    var reader = Reader(bytes: bytes)
    do {
      let value = try reader.value()
      return (value, reader.index)
    } catch Reader.Failure.incomplete {
      return nil
    }
  }

  public enum DecodingError: Error {
    case unknownFormat(UInt8)
  }
}

private func bigEndian(_ value: UInt64, count: Int) -> [UInt8] {
  (0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> (UInt64($0) * 8)) }
}

private struct Reader {
  enum Failure: Error { case incomplete }

  let bytes: [UInt8]
  var index = 0

  mutating func byte() throws -> UInt8 {
    guard index < bytes.count else { throw Failure.incomplete }
    defer { index += 1 }
    return bytes[index]
  }

  mutating func take(_ count: Int) throws -> [UInt8] {
    guard count >= 0, index + count <= bytes.count else { throw Failure.incomplete }
    defer { index += count }
    return Array(bytes[index..<(index + count)])
  }

  mutating func unsigned(_ count: Int) throws -> UInt64 {
    try take(count).reduce(0) { $0 << 8 | UInt64($1) }
  }

  mutating func signed(_ count: Int) throws -> Int64 {
    let raw = try unsigned(count)
    let shift = UInt64(64 - count * 8)
    return Int64(bitPattern: raw << shift) >> Int64(shift)
  }

  mutating func string(_ count: Int) throws -> MessagePack {
    .string(String(decoding: try take(count), as: UTF8.self))
  }

  mutating func array(_ count: Int) throws -> MessagePack {
    var values: [MessagePack] = []
    for _ in 0..<count { values.append(try value()) }
    return .array(values)
  }

  mutating func map(_ count: Int) throws -> MessagePack {
    var pairs: [(key: MessagePack, value: MessagePack)] = []
    for _ in 0..<count { pairs.append((try value(), try value())) }
    return .map(pairs)
  }

  mutating func ext(_ count: Int) throws -> MessagePack {
    let type = Int8(bitPattern: try byte())
    return .ext(type, try take(count))
  }

  mutating func value() throws -> MessagePack {
    let marker = try byte()
    switch marker {
    case 0x00...0x7F: return .int(Int64(marker))
    case 0x80...0x8F: return try map(Int(marker & 0x0F))
    case 0x90...0x9F: return try array(Int(marker & 0x0F))
    case 0xA0...0xBF: return try string(Int(marker & 0x1F))
    case 0xC0: return .null
    case 0xC2: return .bool(false)
    case 0xC3: return .bool(true)
    case 0xC4: return .binary(try take(Int(try unsigned(1))))
    case 0xC5: return .binary(try take(Int(try unsigned(2))))
    case 0xC6: return .binary(try take(Int(try unsigned(4))))
    case 0xC7: return try ext(Int(try unsigned(1)))
    case 0xC8: return try ext(Int(try unsigned(2)))
    case 0xC9: return try ext(Int(try unsigned(4)))
    case 0xCA: return .double(Double(Float(bitPattern: UInt32(try unsigned(4)))))
    case 0xCB: return .double(Double(bitPattern: try unsigned(8)))
    case 0xCC: return .int(Int64(try unsigned(1)))
    case 0xCD: return .int(Int64(try unsigned(2)))
    case 0xCE: return .int(Int64(try unsigned(4)))
    case 0xCF: return .int(Int64(bitPattern: try unsigned(8)))
    case 0xD0: return .int(try signed(1))
    case 0xD1: return .int(try signed(2))
    case 0xD2: return .int(try signed(4))
    case 0xD3: return .int(try signed(8))
    case 0xD4: return try ext(1)
    case 0xD5: return try ext(2)
    case 0xD6: return try ext(4)
    case 0xD7: return try ext(8)
    case 0xD8: return try ext(16)
    case 0xD9: return try string(Int(try unsigned(1)))
    case 0xDA: return try string(Int(try unsigned(2)))
    case 0xDB: return try string(Int(try unsigned(4)))
    case 0xDC: return try array(Int(try unsigned(2)))
    case 0xDD: return try array(Int(try unsigned(4)))
    case 0xDE: return try map(Int(try unsigned(2)))
    case 0xDF: return try map(Int(try unsigned(4)))
    case 0xE0...0xFF: return .int(Int64(Int8(bitPattern: marker)))
    default: throw MessagePack.DecodingError.unknownFormat(marker)
    }
  }
}
