//
//  SpirvEntryPoints.swift
//  NucleantUI
//

/// The entry points a SPIR-V module declares, by stage — what decides
/// whether a shader is dispatched over every pixel or drawn as geometry.
///
/// Read from the module's `OpEntryPoint`s rather than from any source: the
/// module already says what it is, whatever it was written in.
struct SpirvEntryPoints: Equatable {
    var compute: String?
    var vertex: String?
    var fragment: String?

    /// A vertex stage beside a fragment one: drawn with a graphics pipeline.
    var isGraphics: Bool { vertex != nil && fragment != nil }

    init(_ words: [UInt32]) {
        // Header: magic, version, generator, bound, schema.
        guard words.count > 5, words[0] == 0x0723_0203 else { return }
        var index = 5
        while index < words.count {
            let count = Int(words[index] >> 16)
            let opcode = words[index] & 0xFFFF
            guard count > 0, index + count <= words.count else { return }
            // OpEntryPoint: execution model, function id, name, interface ids.
            if opcode == 15, count >= 4 {
                let name = Self.string(words[(index + 3)..<(index + count)])
                switch words[index + 1] {
                case 0: vertex = vertex ?? name
                case 4: fragment = fragment ?? name
                case 5: compute = compute ?? name
                default: break
                }
            }
            // OpFunction: the entry points are all declared before the first.
            if opcode == 54 { return }
            index += count
        }
    }

    /// A SPIR-V literal string: UTF-8, little-endian in each word, ended by
    /// a zero byte.
    private static func string(_ words: ArraySlice<UInt32>) -> String {
        var bytes: [UInt8] = []
        for word in words {
            for shift in stride(from: 0, to: 32, by: 8) {
                let byte = UInt8((word >> UInt32(shift)) & 0xFF)
                if byte == 0 { return String(decoding: bytes, as: UTF8.self) }
                bytes.append(byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
