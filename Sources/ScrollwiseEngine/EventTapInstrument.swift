#if SCROLLWISE_INSTRUMENT
import Darwin
import Synchronization

/// Callback timing and fault injection, compiled only into instrumentation
/// builds (`swift build -Xswiftc -DSCROLLWISE_INSTRUMENT`). A normal build
/// contains none of this — not the clock reads, not the storage.
///
/// Samples go into storage allocated up front, so recording one is a clock read
/// and a store: the measurement does not allocate inside the thing it measures.
public final class EventTapInstrument: @unchecked Sendable {

    public static let capacity = 1 << 16

    private let samples: UnsafeMutablePointer<UInt64>
    /// Written on the tap thread only; read after the thread has exited.
    private var recorded = 0
    private let pendingStall = Atomic<UInt64>(0)

    init() {
        samples = .allocate(capacity: Self.capacity)
        samples.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        samples.deinitialize(count: Self.capacity)
        samples.deallocate()
    }

    static func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    func record(since start: UInt64) {
        samples[recorded & (Self.capacity - 1)] = Self.now() &- start
        recorded &+= 1
    }

    /// Makes the next scroll callback block for this long, so a test can make
    /// macOS disable the tap for unresponsiveness and watch it recover.
    public func stallNextCallback(nanoseconds: UInt64) {
        pendingStall.store(nanoseconds, ordering: .relaxed)
    }

    func consumeStall() {
        let nanoseconds = pendingStall.exchange(0, ordering: .relaxed)
        guard nanoseconds > 0 else { return }
        var request = timespec(
            tv_sec: Int(nanoseconds / 1_000_000_000),
            tv_nsec: Int(nanoseconds % 1_000_000_000)
        )
        nanosleep(&request, nil)
    }

    /// Callback durations in nanoseconds, oldest first. Once more than
    /// `capacity` have been recorded, these are the most recent `capacity`.
    /// Only meaningful after `EventTapController.stop()` has returned, when the
    /// tap thread that writes them has exited.
    public func durations() -> [UInt64] {
        let buffer = UnsafeBufferPointer(start: samples, count: Self.capacity)
        guard recorded > Self.capacity else { return Array(buffer.prefix(recorded)) }
        // The storage is a ring: after it wraps, the oldest sample is the one
        // the next write would replace.
        let oldest = recorded & (Self.capacity - 1)
        return Array(buffer[oldest...]) + Array(buffer[..<oldest])
    }
}
#endif
