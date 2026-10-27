//
//  AudioPlayer+Windows.swift
//  NucleantAudio
//
//  Not yet: Windows' output is WASAPI (an IAudioClient in shared mode, fed
//  from its own thread), which is a backend of its own to write. Until then
//  this compiles and fails visibly — `AudioPlayer.init` throws
//  `unsupportedPlatform` — so the rest of the package builds and runs on
//  Windows.
//

#if os(Windows)
final class AudioBackend<Processor: AudioProcessor> {
    var sampleRate: Double { 0 }

    init(channels: Int, box: ProcessorBox<Processor>) throws {
        throw AudioPlayerError.unsupportedPlatform
    }

    func start() throws {
        throw AudioPlayerError.unsupportedPlatform
    }

    func stop() {}
}
#endif
