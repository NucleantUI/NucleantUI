//
//  AudioPlayer+Linux.swift
//  NucleantAudio
//
//  ALSA's default PCM: on a desktop that is the sound server — PipeWire's or
//  PulseAudio's ALSA plugin, so the player is a stream in the mixer like any
//  other app's — and on a bare system the hardware, shared through dmix.
//  libasound is opened at run time rather than linked, so building needs no
//  ALSA headers, and a machine without it gets `outputUnavailable` instead
//  of an app that won't start.
//
//  ALSA is fed rather than calling back: a thread of the player's own asks
//  the processor for a period at a time and writes it, the write blocking
//  while the device's buffer is full. The thread runs from `start` to
//  `stop`; the device stays open from `init` to the player's end.
//

#if os(Linux)
import Foundation
import Glibc

final class AudioBackend<Processor: AudioProcessor> {
    let sampleRate: Double
    private let output: ALSAOutput<Processor>
    private var feeder: Feeder?

    init(channels: Int, box: ProcessorBox<Processor>) throws {
        output = try ALSAOutput(channels: channels, box: box)
        sampleRate = output.sampleRate
    }

    func start() throws {
        guard feeder == nil else { return }
        try output.prepare()
        let output = output
        feeder = Feeder { output.writePeriod() }
    }

    func stop() {
        guard let feeder else { return }
        feeder.stop()
        self.feeder = nil
        // What was written and not yet played goes, as on the other
        // platforms: a stopped player is silent at once.
        output.drop()
    }

    deinit {
        stop()
    }
}

/// The open PCM, and the buffer one period is rendered into. Touched by the
/// feeding thread while it runs and by the player otherwise — never both, as
/// `stop` waits for the thread to end.
private final class ALSAOutput<Processor: AudioProcessor>: @unchecked Sendable {
    /// Not the hardware's rate, which ALSA's default PCM doesn't say, but
    /// the rate PipeWire and PulseAudio run at unless set otherwise. The
    /// server, or ALSA's plug layer, converts if the device runs at another.
    static var preferredRate: UInt32 { 48_000 }

    /// How far ahead of the speaker the processor is: the device's buffer,
    /// written a quarter of it at a time.
    static var latency: UInt32 { 30_000 }  // µs

    let sampleRate: Double
    private let channels: Int
    private let alsa: ALSA
    private let pcm: OpaquePointer
    private let box: ProcessorBox<Processor>
    private let period: Int
    private let buffer: UnsafeMutableBufferPointer<Float>

    init(channels: Int, box: ProcessorBox<Processor>) throws {
        guard let alsa = ALSA.shared else {
            throw AudioPlayerError.outputUnavailable("libasound.so.2 could not be loaded")
        }
        var opened: OpaquePointer?
        var result = alsa.open(&opened, "default", ALSA.streamPlayback, 0)
        guard result == 0, let pcm = opened else {
            throw AudioPlayerError.outputUnavailable("ALSA could not open the default output: \(alsa.describe(result))")
        }
        result = alsa.setParams(
            pcm, ALSA.formatFloatLE, ALSA.accessInterleaved,
            UInt32(channels), Self.preferredRate, 1, Self.latency
        )
        guard result == 0 else {
            _ = alsa.close(pcm)
            if result == -EINVAL {
                throw AudioPlayerError.unsupportedFormat(channels: channels, sampleRate: Double(Self.preferredRate))
            }
            throw AudioPlayerError.outputUnavailable("ALSA could not set up the default output: \(alsa.describe(result))")
        }
        var bufferSize: UInt = 0
        var periodSize: UInt = 0
        _ = alsa.getParams(pcm, &bufferSize, &periodSize)
        let period = periodSize > 0 ? Int(periodSize) : Int(Self.preferredRate / 100)

        self.alsa = alsa
        self.pcm = pcm
        self.box = box
        self.channels = channels
        self.period = period
        sampleRate = Double(Self.preferredRate)
        buffer = .allocate(capacity: period * channels)
        buffer.initialize(repeating: 0)
    }

    deinit {
        _ = alsa.close(pcm)
        buffer.deallocate()
    }

    /// Ready to play again after `drop`; does nothing to a PCM that is.
    func prepare() throws {
        let result = alsa.prepare(pcm)
        guard result == 0 else {
            throw AudioPlayerError.outputUnavailable("ALSA could not start the output: \(alsa.describe(result))")
        }
    }

    func drop() {
        _ = alsa.drop(pcm)
    }

    /// One period from the processor, written out; on the feeding thread.
    /// An underrun — the thread held up longer than the buffer lasts — is a
    /// click, recovered from, and the period written after it. `false`
    /// when the device has gone, which ends the thread.
    func writePeriod() -> Bool {
        box.process(into: buffer, channels: channels, sampleRate: sampleRate)
        guard let base = buffer.baseAddress else { return false }
        var written = 0
        while written < period {
            let frames = alsa.writei(pcm, base + written * channels, UInt(period - written))
            if frames >= 0 {
                written += frames
            } else if alsa.recover(pcm, Int32(frames), 1) < 0 {
                let message = "NucleantAudio: the output stopped: \(alsa.describe(Int32(frames)))\n"
                FileHandle.standardError.write(Data(message.utf8))
                return false
            }
        }
        return true
    }
}

/// A thread that calls `body` until it returns `false` or `stop` is called.
private final class Feeder: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private let finished = DispatchSemaphore(value: 0)

    init(_ body: @escaping @Sendable () -> Bool) {
        let thread = Thread { [self] in
            while isRunning, body() {}
            finished.signal()
        }
        thread.name = "NucleantAudio output"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private var isRunning: Bool {
        lock.withLock { running }
    }

    /// Returns once the thread has: within a period, the longest a write
    /// blocks.
    func stop() {
        lock.withLock { running = false }
        finished.wait()
    }
}

/// The few libasound calls the player makes, looked up once.
private struct ALSA: @unchecked Sendable {
    // snd_pcm_stream_t, snd_pcm_format_t, snd_pcm_access_t.
    static let streamPlayback: Int32 = 0
    static let formatFloatLE: Int32 = 14
    static let accessInterleaved: Int32 = 3

    typealias Open = @convention(c) (UnsafeMutablePointer<OpaquePointer?>, UnsafePointer<CChar>, Int32, Int32) -> Int32
    typealias SetParams = @convention(c) (OpaquePointer, Int32, Int32, UInt32, UInt32, Int32, UInt32) -> Int32
    typealias GetParams = @convention(c) (OpaquePointer, UnsafeMutablePointer<UInt>, UnsafeMutablePointer<UInt>) -> Int32
    typealias WriteI = @convention(c) (OpaquePointer, UnsafeRawPointer, UInt) -> Int
    typealias Recover = @convention(c) (OpaquePointer, Int32, Int32) -> Int32
    typealias Call = @convention(c) (OpaquePointer) -> Int32
    typealias StrError = @convention(c) (Int32) -> UnsafePointer<CChar>?

    let open: Open
    let setParams: SetParams
    let getParams: GetParams
    let writei: WriteI
    let recover: Recover
    let prepare: Call
    let drop: Call
    let close: Call
    let strerror: StrError

    static let shared = ALSA()

    private init?() {
        guard let library = dlopen("libasound.so.2", RTLD_NOW | RTLD_LOCAL) else { return nil }
        func symbol<Function>(_ name: String, as _: Function.Type) -> Function? {
            dlsym(library, name).map { unsafeBitCast($0, to: Function.self) }
        }
        guard
            let open = symbol("snd_pcm_open", as: Open.self),
            let setParams = symbol("snd_pcm_set_params", as: SetParams.self),
            let getParams = symbol("snd_pcm_get_params", as: GetParams.self),
            let writei = symbol("snd_pcm_writei", as: WriteI.self),
            let recover = symbol("snd_pcm_recover", as: Recover.self),
            let prepare = symbol("snd_pcm_prepare", as: Call.self),
            let drop = symbol("snd_pcm_drop", as: Call.self),
            let close = symbol("snd_pcm_close", as: Call.self),
            let strerror = symbol("snd_strerror", as: StrError.self)
        else {
            dlclose(library)
            return nil
        }
        self.open = open
        self.setParams = setParams
        self.getParams = getParams
        self.writei = writei
        self.recover = recover
        self.prepare = prepare
        self.drop = drop
        self.close = close
        self.strerror = strerror
    }

    func describe(_ error: Int32) -> String {
        strerror(error).map { String(cString: $0) } ?? "error \(error)"
    }
}
#endif
