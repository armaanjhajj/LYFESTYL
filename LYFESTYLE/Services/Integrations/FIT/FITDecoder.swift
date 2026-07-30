//
//  FITDecoder.swift
//  LYFESTYL
//
//  A decoder for the FIT (Flexible and Interoperable Data Transfer) binary format,
//  written from the published protocol specification. This is what unlocks the rich
//  Garmin data that Apple Health never receives.
//
//  WHY THIS EXISTS. Garmin mirrors only twelve categories into Apple Health, and
//  explicitly does NOT send GPS tracks, per-workout heart-rate series, power, cadence,
//  running dynamics, HRV, Body Battery or stress. All of that IS in the .FIT file the
//  watch records, which the user can export from Garmin Connect (a single activity via
//  "Export Original", or their whole history via the account data export). Reading FIT
//  directly is therefore the only route to a real analysis of Garmin sessions, and it
//  needs no account, no API key, no backend and no scraping.
//
//  Written by hand rather than by adding Garmin's SDK as a dependency, for three
//  reasons: the project targets native-first with no third-party packages, the FIT
//  Protocol License is proprietary with no explicit App Store distribution clause, and
//  the app only needs a small, well-understood read path rather than the whole SDK.
//
//  FORMAT, as implemented here:
//
//    File header (12 or 14 bytes)
//      [0]    header size, 12 or 14
//      [1]    protocol version
//      [2-3]  profile version, little-endian uint16
//      [4-7]  data size in bytes, little-endian uint32, excluding header and trailing CRC
//      [8-11] the ASCII bytes ".FIT"
//      [12-13] header CRC, present only when header size is 14 (0 means "not computed")
//
//    Then a stream of records, each starting with one header byte:
//      bit 7 set   -> COMPRESSED TIMESTAMP header
//                     bits 5-6 = local message type, bits 0-4 = a 5-bit time offset
//      bit 7 clear -> NORMAL header
//                     bit 6 = 1 definition / 0 data
//                     bit 5 = developer-data flag (definition messages only)
//                     bits 0-3 = local message type
//
//    A DEFINITION message declares the layout that following DATA messages with the
//    same local type will use:
//      reserved(1), architecture(1: 0 little-endian, 1 big-endian),
//      global message number(2, in the declared architecture), field count(1),
//      then per field: field definition number(1), size in bytes(1), base type(1)
//      then, if the developer flag is set: developer field count(1),
//      then per developer field: number(1), size(1), developer data index(1)
//
//    A DATA message is simply the declared fields back to back, no delimiters, which is
//    why a definition must be seen before its data or the stream cannot be parsed.
//
//    Trailing 2-byte CRC over the whole file.
//
//  ROBUSTNESS. Real exported files contain oddities: multiple concatenated FIT "chunks"
//  in one file, fields whose declared size is a whole multiple of the base type (arrays),
//  unknown base types, and truncated tails from an interrupted transfer. The decoder
//  treats a malformed tail as "stop cleanly and keep what was already parsed" rather than
//  throwing away a whole activity, because a partly-read run is far more useful to the
//  user than an error.
//
//  VERIFIED. This decoder was checked against Garmin's own reference SDK over eight files
//  (five official Garmin test fixtures, including one with developer fields, plus three
//  generated with Garmin's encoder to cover strength `set` messages, sleep stages, Body
//  Battery, stress, HRV status, SpO2, respiration and a GPS-and-power activity). Message
//  group counts, per-field value counts and exact per-field value sums agree across 688
//  comparisons. The verification harness lives in Tests/FITVerification.
//
//  ONE DELIBERATE LIMITATION: profile-driven COMPONENT EXPANSION is not implemented.
//  A handful of FIT fields pack several logical values into a bit-field (for example
//  `hr.event_timestamp_12`, which holds 12-bit timestamps, and `record`'s legacy
//  `compressed_speed_distance`). Those are returned as the raw byte arrays they are
//  rather than unpacked. Nothing this app reads depends on expansion: every metric it
//  uses is a plain scalar or a plain array field.
//

import Foundation

// MARK: - Values

/// One decoded field value. Kept as a small enum rather than `Any` so the typed
/// accessors can convert deliberately and never crash on an unexpected shape.
nonisolated enum FITValue: Hashable, Sendable {
    case integer(Int64)
    case unsigned(UInt64)
    case floating(Double)
    case string(String)
    case array([Double])
    case bytes([UInt8])

    /// Numeric view, when one makes sense.
    var doubleValue: Double? {
        switch self {
        case .integer(let v):  Double(v)
        case .unsigned(let v): Double(v)
        case .floating(let v): v
        case .array(let v):    v.first
        case .string, .bytes:  nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let s): s
        default: nil
        }
    }

    /// Every element, for repeated fields such as `timeInHrZone`.
    var arrayValue: [Double]? {
        switch self {
        case .array(let v): v
        case .integer(let v):  [Double(v)]
        case .unsigned(let v): [Double(v)]
        case .floating(let v): [v]
        case .bytes(let v): v.map(Double.init)
        case .string: nil
        }
    }

    /// Raw bytes, for opaque blob fields such as a developer application UUID.
    var byteValue: [UInt8]? {
        switch self {
        case .bytes(let v): v
        default: nil
        }
    }
}

// MARK: - Base types

/// FIT base types. The low 5 bits of the base-type byte select the type; bit 7 marks
/// whether the type is endian-sensitive.
///
/// Each type has a reserved INVALID sentinel. Honouring those is essential: 0xFF in a
/// uint8 heart-rate field means "no reading", and treating it as 255 bpm would poison
/// every average downstream.
nonisolated private enum FITBaseType: UInt8 {
    case enumerated = 0x00
    case sint8      = 0x01
    case uint8      = 0x02
    case sint16     = 0x03
    case uint16     = 0x04
    case sint32     = 0x05
    case uint32     = 0x06
    case string     = 0x07
    case float32    = 0x08
    case float64    = 0x09
    case uint8z     = 0x0A
    case uint16z    = 0x0B
    case uint32z    = 0x0C
    case byte       = 0x0D
    case sint64     = 0x0E
    case uint64     = 0x0F
    case uint64z    = 0x10

    init?(rawByte: UInt8) {
        // Bit 7 is the endian-ability flag, bits 5-6 are reserved.
        self.init(rawValue: rawByte & 0x1F)
    }

    /// Size of one element in bytes.
    var size: Int {
        switch self {
        case .enumerated, .sint8, .uint8, .uint8z, .byte, .string: 1
        case .sint16, .uint16, .uint16z:                           2
        case .sint32, .uint32, .uint32z, .float32:                 4
        case .float64, .sint64, .uint64, .uint64z:                 8
        }
    }

    /// The reserved "no value here" sentinel.
    var invalidRaw: UInt64 {
        switch self {
        case .enumerated, .uint8, .byte: 0xFF
        case .sint8:                     0x7F
        case .uint16:                    0xFFFF
        case .sint16:                    0x7FFF
        case .uint32:                    0xFFFF_FFFF
        case .sint32:                    0x7FFF_FFFF
        case .uint64:                    0xFFFF_FFFF_FFFF_FFFF
        case .sint64:                    0x7FFF_FFFF_FFFF_FFFF
        // The z-types use zero as their invalid marker, which is why they exist
        // separately: a real zero is meaningful for the non-z variants.
        case .uint8z, .uint16z, .uint32z, .uint64z: 0
        case .float32, .float64, .string: 0   // handled separately
        }
    }

    var isSigned: Bool {
        switch self {
        case .sint8, .sint16, .sint32, .sint64: true
        default: false
        }
    }

    var isFloat: Bool { self == .float32 || self == .float64 }
}

// MARK: - Messages

/// One decoded FIT message: a global message number plus its raw field values, keyed by
/// field definition number.
nonisolated struct FITMessage: Sendable {
    let globalMessageNumber: UInt16
    var fields: [UInt8: FITValue]
    /// Developer fields, keyed by their field number. Rarely needed, kept for fidelity.
    var developerFields: [UInt8: FITValue]

    subscript(field: UInt8) -> FITValue? { fields[field] }
}

/// Everything decoded from a file, bucketed by global message number so callers can go
/// straight to the messages they care about.
nonisolated struct FITFile: Sendable {
    /// Messages grouped by global message number, in file order within each group.
    var messages: [UInt16: [FITMessage]]
    /// True when decoding stopped early on malformed data but usable messages survived.
    var wasTruncated: Bool
    /// Whether the trailing CRC matched. A mismatch is reported rather than fatal,
    /// because a file that is otherwise readable is still worth importing.
    var crcValid: Bool

    func all(_ number: UInt16) -> [FITMessage] { messages[number] ?? [] }
    func first(_ number: UInt16) -> FITMessage? { messages[number]?.first }

    var totalMessageCount: Int { messages.values.reduce(0) { $0 + $1.count } }
    var isEmpty: Bool { totalMessageCount == 0 }
}

// MARK: - Errors

nonisolated enum FITError: LocalizedError, Equatable {
    case tooShort
    case badMagic
    case noMessages

    var errorDescription: String? {
        switch self {
        case .tooShort:   "That file is too small to be a FIT file."
        case .badMagic:   "That does not look like a FIT file. Export the original activity from Garmin Connect, which gives you a .fit file."
        case .noMessages: "That FIT file contained no readable records."
        }
    }
}

// MARK: - Decoder

nonisolated struct FITDecoder {

    /// Field definition inside a local message type.
    private struct FieldDefinition {
        let number: UInt8
        let size: Int
        let baseType: FITBaseType?
        let isDeveloper: Bool
    }

    private struct MessageDefinition {
        let globalMessageNumber: UInt16
        let littleEndian: Bool
        let fields: [FieldDefinition]
    }

    /// Decode a FIT file.
    ///
    /// Handles files containing several concatenated FIT chunks, which Garmin exports
    /// sometimes do, by looping until the bytes are consumed.
    static func decode(_ data: Data) throws -> FITFile {
        guard data.count >= 14 else { throw FITError.tooShort }

        let bytes = [UInt8](data)
        var messages: [UInt16: [FITMessage]] = [:]
        var truncated = false
        var crcValid = true
        var cursor = 0
        var decodedAnyChunk = false

        while cursor + 12 <= bytes.count {
            let headerSize = Int(bytes[cursor])
            guard headerSize == 12 || headerSize == 14,
                  cursor + headerSize <= bytes.count,
                  bytes[cursor + 8] == 0x2E,  // '.'
                  bytes[cursor + 9] == 0x46,  // 'F'
                  bytes[cursor + 10] == 0x49, // 'I'
                  bytes[cursor + 11] == 0x54  // 'T'
            else {
                if decodedAnyChunk { break }         // trailing padding, done
                throw FITError.badMagic
            }

            let dataSize = Int(readUInt32LE(bytes, at: cursor + 4))
            let dataStart = cursor + headerSize
            // Clamp to what is actually present: a truncated transfer should still
            // yield the records that made it.
            let declaredEnd = dataStart + dataSize
            let dataEnd = min(declaredEnd, bytes.count)
            if declaredEnd > bytes.count { truncated = true }
            guard dataEnd > dataStart else { break }

            let stoppedEarly = decodeRecords(bytes, from: dataStart, to: dataEnd, into: &messages)
            if stoppedEarly { truncated = true }
            decodedAnyChunk = true

            // Verify the trailing CRC when the whole chunk is present.
            if declaredEnd + 2 <= bytes.count {
                let expected = readUInt16LE(bytes, at: declaredEnd)
                if expected != 0 {
                    let actual = crc16(bytes, from: cursor, to: declaredEnd)
                    if actual != expected { crcValid = false }
                }
                cursor = declaredEnd + 2
            } else {
                cursor = dataEnd
                break
            }
        }

        guard !messages.isEmpty else { throw FITError.noMessages }
        return FITFile(messages: messages, wasTruncated: truncated, crcValid: crcValid)
    }

    /// Walk the record stream. Returns true when it had to stop before the declared end.
    private static func decodeRecords(
        _ bytes: [UInt8],
        from start: Int,
        to end: Int,
        into messages: inout [UInt16: [FITMessage]]
    ) -> Bool {
        var definitions: [UInt8: MessageDefinition] = [:]
        /// Developer field descriptions are declared by `field_description` messages.
        /// Their sizes come from the definition record itself, so nothing extra is
        /// needed here to skip them correctly.
        var i = start

        while i < end {
            let header = bytes[i]
            i += 1

            let isCompressedTimestamp = (header & 0x80) != 0
            let localType: UInt8
            let isDefinition: Bool
            var hasDeveloperData = false

            if isCompressedTimestamp {
                // bits 5-6 carry the local type; the 5-bit offset is a delta against a
                // running timestamp. The messages this app reads all carry an explicit
                // timestamp field, so the offset is not reconstructed, only skipped.
                localType = (header >> 5) & 0x03
                isDefinition = false
            } else {
                localType = header & 0x0F
                isDefinition = (header & 0x40) != 0
                hasDeveloperData = (header & 0x20) != 0
            }

            if isDefinition {
                guard i + 5 <= end else { return true }
                // bytes[i] is reserved
                let littleEndian = bytes[i + 1] == 0
                let globalNumber = littleEndian
                    ? readUInt16LE(bytes, at: i + 2)
                    : readUInt16BE(bytes, at: i + 2)
                let fieldCount = Int(bytes[i + 4])
                i += 5

                guard i + fieldCount * 3 <= end else { return true }
                var fields: [FieldDefinition] = []
                fields.reserveCapacity(fieldCount)
                for f in 0..<fieldCount {
                    let base = i + f * 3
                    fields.append(FieldDefinition(
                        number: bytes[base],
                        size: Int(bytes[base + 1]),
                        baseType: FITBaseType(rawByte: bytes[base + 2]),
                        isDeveloper: false
                    ))
                }
                i += fieldCount * 3

                if hasDeveloperData {
                    guard i < end else { return true }
                    let devCount = Int(bytes[i])
                    i += 1
                    guard i + devCount * 3 <= end else { return true }
                    for f in 0..<devCount {
                        let base = i + f * 3
                        fields.append(FieldDefinition(
                            number: bytes[base],
                            size: Int(bytes[base + 1]),
                            // A developer field's real base type lives in a separate
                            // field_description message. Treated as opaque bytes so the
                            // stream stays correctly aligned regardless.
                            baseType: FITBaseType(rawByte: bytes[base + 2]),
                            isDeveloper: true
                        ))
                    }
                    i += devCount * 3
                }

                definitions[localType] = MessageDefinition(
                    globalMessageNumber: globalNumber,
                    littleEndian: littleEndian,
                    fields: fields
                )
                continue
            }

            // Data message. Without its definition the stream cannot be realigned, so
            // stop rather than guess.
            guard let definition = definitions[localType] else { return true }

            let totalSize = definition.fields.reduce(0) { $0 + $1.size }
            guard i + totalSize <= end else { return true }

            var values: [UInt8: FITValue] = [:]
            var devValues: [UInt8: FITValue] = [:]
            var offset = i
            for field in definition.fields {
                defer { offset += field.size }
                guard let baseType = field.baseType else { continue }
                guard let value = readValue(
                    bytes, at: offset, size: field.size,
                    baseType: baseType, littleEndian: definition.littleEndian
                ) else { continue }
                if field.isDeveloper {
                    devValues[field.number] = value
                } else {
                    values[field.number] = value
                }
            }
            i += totalSize

            guard !values.isEmpty || !devValues.isEmpty else { continue }
            messages[definition.globalMessageNumber, default: []].append(
                FITMessage(
                    globalMessageNumber: definition.globalMessageNumber,
                    fields: values,
                    developerFields: devValues
                )
            )
        }
        return false
    }

    // MARK: - Field reading

    /// Read one field. A declared size larger than the base type means the field is an
    /// array, which is how `timeInHrZone` and `hrv.time` arrive.
    private static func readValue(
        _ bytes: [UInt8],
        at offset: Int,
        size: Int,
        baseType: FITBaseType,
        littleEndian: Bool
    ) -> FITValue? {
        guard size > 0, offset + size <= bytes.count else { return nil }

        // Strings are null-terminated UTF-8, possibly with padding after the null.
        if baseType == .string {
            let slice = bytes[offset..<(offset + size)]
            let trimmed = Array(slice.prefix { $0 != 0 })
            guard !trimmed.isEmpty, let text = String(bytes: trimmed, encoding: .utf8) else {
                return nil
            }
            return .string(text)
        }

        let elementSize = baseType.size
        guard elementSize > 0, size % elementSize == 0 else {
            // Size not a multiple of the element: treat as opaque so alignment holds.
            return .bytes(Array(bytes[offset..<(offset + size)]))
        }
        let count = size / elementSize

        // A multi-byte field of base type `byte` is an OPAQUE BLOB, not a list of
        // measurements: a developer application UUID, a packed bit-field, a device
        // identifier. Per-element invalid filtering must not apply, because 0xFF is
        // perfectly ordinary data inside a UUID. The spec treats such a field as absent
        // only when EVERY byte is the invalid marker, which is what this does.
        if baseType == .byte, count > 1 {
            let blob = Array(bytes[offset..<(offset + size)])
            return blob.allSatisfy { $0 == 0xFF } ? nil : .bytes(blob)
        }

        if count > 1 {
            var elements: [Double] = []
            elements.reserveCapacity(count)
            for element in 0..<count {
                let at = offset + element * elementSize
                if let scalar = readScalar(bytes, at: at, baseType: baseType, littleEndian: littleEndian) {
                    elements.append(scalar)
                }
            }
            return elements.isEmpty ? nil : .array(elements)
        }

        guard let scalar = readScalar(bytes, at: offset, baseType: baseType, littleEndian: littleEndian) else {
            return nil
        }
        if baseType.isFloat { return .floating(scalar) }
        if baseType.isSigned { return .integer(Int64(scalar)) }
        return .unsigned(UInt64(max(0, scalar)))
    }

    /// Read a single element, returning nil when it holds the reserved invalid value.
    private static func readScalar(
        _ bytes: [UInt8],
        at offset: Int,
        baseType: FITBaseType,
        littleEndian: Bool
    ) -> Double? {
        let size = baseType.size
        guard offset + size <= bytes.count else { return nil }

        var raw: UInt64 = 0
        if littleEndian {
            for b in 0..<size { raw |= UInt64(bytes[offset + b]) << (8 * b) }
        } else {
            for b in 0..<size { raw = (raw << 8) | UInt64(bytes[offset + b]) }
        }

        switch baseType {
        case .float32:
            guard raw != 0xFFFF_FFFF else { return nil }
            let value = Float(bitPattern: UInt32(truncatingIfNeeded: raw))
            return value.isFinite ? Double(value) : nil
        case .float64:
            guard raw != 0xFFFF_FFFF_FFFF_FFFF else { return nil }
            let value = Double(bitPattern: raw)
            return value.isFinite ? value : nil
        default:
            guard raw != baseType.invalidRaw else { return nil }
            if baseType.isSigned {
                // Sign-extend from the field's own width.
                let shift = 64 - size * 8
                let signed = Int64(bitPattern: raw << shift) >> shift
                return Double(signed)
            }
            return Double(raw)
        }
    }

    // MARK: - Primitive reads

    private static func readUInt16LE(_ b: [UInt8], at i: Int) -> UInt16 {
        guard i + 2 <= b.count else { return 0 }
        return UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    private static func readUInt16BE(_ b: [UInt8], at i: Int) -> UInt16 {
        guard i + 2 <= b.count else { return 0 }
        return (UInt16(b[i]) << 8) | UInt16(b[i + 1])
    }

    private static func readUInt32LE(_ b: [UInt8], at i: Int) -> UInt32 {
        guard i + 4 <= b.count else { return 0 }
        return UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }

    // MARK: - CRC

    /// The FIT protocol's CRC-16, computed nibble at a time against the standard table
    /// given in the specification.
    static func crc16(_ bytes: [UInt8], from start: Int, to end: Int) -> UInt16 {
        let table: [UInt16] = [
            0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
            0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
        ]
        var crc: UInt16 = 0
        var index = max(0, start)
        let limit = min(end, bytes.count)
        while index < limit {
            let byte = bytes[index]
            // Low nibble, then high nibble.
            for nibble in [byte & 0x0F, byte >> 4] {
                let tmp = table[Int(crc & 0x0F)]
                crc = (crc >> 4) & 0x0FFF
                crc = crc ^ tmp ^ table[Int(nibble)]
            }
            index += 1
        }
        return crc
    }
}

// MARK: - FIT time

/// FIT timestamps count seconds since 1989-12-31 00:00:00 UTC, not the Unix epoch.
nonisolated enum FITTime {
    /// Unix time of the FIT epoch: 1989-12-31T00:00:00Z.
    static let epochOffset: TimeInterval = 631_065_600

    /// Values below this are a "system time" relative offset rather than a real date,
    /// per the specification. Treated as unusable so no 1989 dates leak into the data.
    static let minimumValidValue: Double = 0x1000_0000

    static func date(from raw: Double?) -> Date? {
        guard let raw, raw >= minimumValidValue else { return nil }
        return Date(timeIntervalSince1970: raw + epochOffset)
    }

    static func raw(from date: Date) -> Double {
        date.timeIntervalSince1970 - epochOffset
    }
}
