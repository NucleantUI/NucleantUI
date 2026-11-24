//
//  AudioFileLoader+Linux.swift
//  NucleantAudio
//
//  libsndfile, which every desktop has (the sound servers depend on it): it
//  reads WAV, AIFF, CAF, FLAC, Ogg Vorbis and Opus, and — from 1.1, built
//  with mpg123, as distributions do — MP3, every one of them out as Float
//  samples scaled to ±1. AAC/M4A it does not read; those files are
//  `unreadable` here. Opened at run time rather than linked, like ALSA for
//  the player, so building needs no headers, and a machine without it gets
//  `decoderUnavailable`.
//

#if os(Linux)
import Foundation
import Glibc

extension AudioFileLoader {
    func decode(_ url: URL) throws -> AudioClip {
        guard let sndfile = SndFile.shared else {
            throw AudioFileError.decoderUnavailable("libsndfile.so.1 could not be loaded")
        }
        // SF_INFO: frames (Int64) at 0, then the Int32s samplerate,
        // channels, format, sections, seekable — 32 bytes on every 64-bit
        // ABI, read by offset here rather than trusting a Swift struct to lay
        // out the same way.
        let info = UnsafeMutableRawPointer.allocate(byteCount: 32, alignment: 8)
        defer { info.deallocate() }
        info.initializeMemory(as: UInt8.self, repeating: 0, count: 32)
        let opened = url.withUnsafeFileSystemRepresentation { path in
            path.flatMap { sndfile.open($0, SndFile.read, info) }
        }
        guard let file = opened else { throw AudioFileError.unreadable(url) }
        defer { _ = sndfile.close(file) }

        let frameCount = info.load(fromByteOffset: 0, as: Int64.self)
        let sampleRate = Int(info.load(fromByteOffset: 8, as: Int32.self))
        let channelCount = Int(info.load(fromByteOffset: 12, as: Int32.self))
        guard sampleRate > 0, channelCount > 0 else { throw AudioFileError.unreadable(url) }

        var channels = [[Float]](repeating: [], count: channelCount)
        // The count is a promise only some formats keep exactly (an MP3's
        // is an estimate), so it sizes the arrays and the reading goes on to
        // the end of the file regardless.
        if frameCount > 0, frameCount < Int64(Int32.max) {
            for channel in channels.indices { channels[channel].reserveCapacity(Int(frameCount)) }
        }
        let chunk = 16_384
        var interleaved = [Float](repeating: 0, count: chunk * channelCount)
        while true {
            let read = interleaved.withUnsafeMutableBufferPointer { buffer in
                Int(sndfile.readFloat(file, buffer.baseAddress!, Int64(chunk)))
            }
            guard read > 0 else { break }
            interleaved.withUnsafeBufferPointer { samples in
                for channel in 0..<channelCount {
                    for frame in 0..<read {
                        channels[channel].append(samples[frame * channelCount + channel])
                    }
                }
            }
        }
        guard sndfile.error(file) == 0, !channels[0].isEmpty else { throw AudioFileError.unreadable(url) }
        return AudioClip(sampleRate: Double(sampleRate), channels: channels)
    }
}

/// The few libsndfile calls the loader makes, looked up once.
private struct SndFile: @unchecked Sendable {
    /// SFM_READ.
    static let read: Int32 = 0x10

    typealias Open = @convention(c) (UnsafePointer<CChar>, Int32, UnsafeMutableRawPointer) -> OpaquePointer?
    typealias ReadFloat = @convention(c) (OpaquePointer, UnsafeMutablePointer<Float>, Int64) -> Int64
    typealias Call = @convention(c) (OpaquePointer) -> Int32

    let open: Open
    let readFloat: ReadFloat
    let error: Call
    let close: Call

    static let shared = SndFile()

    private init?() {
        guard let library = dlopen("libsndfile.so.1", RTLD_NOW | RTLD_LOCAL) else { return nil }
        func symbol<Function>(_ name: String, as _: Function.Type) -> Function? {
            dlsym(library, name).map { unsafeBitCast($0, to: Function.self) }
        }
        guard
            let open = symbol("sf_open", as: Open.self),
            let readFloat = symbol("sf_readf_float", as: ReadFloat.self),
            let error = symbol("sf_error", as: Call.self),
            let close = symbol("sf_close", as: Call.self)
        else {
            dlclose(library)
            return nil
        }
        self.open = open
        self.readFloat = readFloat
        self.error = error
        self.close = close
    }
}
#endif
