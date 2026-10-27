//
//  AudioFileLoader+Windows.swift
//  NucleantAudio
//
//  Not yet: Windows decodes through Media Foundation (an IMFSourceReader
//  asked for float PCM), to be written with the WASAPI player. Until then
//  loading throws `unsupportedPlatform`.
//

#if os(Windows)
import Foundation

extension AudioFileLoader {
    func decode(_ url: URL) throws -> AudioClip {
        throw AudioFileError.unsupportedPlatform
    }
}
#endif
