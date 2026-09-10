import Darwin
import Foundation

/// Makes sure only one copy of Scrollwise runs per user.
///
/// Each copy installs its own event tap, and two taps flip every scroll event
/// twice — no reversal at all, while both copies read "Reversing". It happens
/// easily: a copy opened from the disk image and another from Applications, or a
/// login-item launch racing a manual one.
///
/// An exclusive `flock` rather than a look at `NSRunningApplication`: that list
/// is a snapshot, so two copies launched in the same instant could each miss the
/// other and both stay. Taking the lock is atomic in the kernel, and the kernel
/// releases it when the process exits, however it exits — a crash leaves nothing
/// stale behind.
@MainActor
enum SingleInstanceLock {

    enum Outcome: Equatable {
        case acquired
        /// Another copy holds the lock; this one must not install a tap.
        case heldElsewhere
        /// The lock file could not be used. Not a reason to refuse to run.
        case unavailable(String)
    }

    /// Held open for the life of the process; closing it would release the lock.
    private static var descriptor: Int32 = -1

    /// Per user, because each login session has its own event stream and may
    /// run its own copy.
    private static var path: String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("engineer.riteshrana.scrollwise.instance.lock").path
    }

    static func acquire() -> Outcome {
        guard descriptor < 0 else { return .acquired }
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return .unavailable(String(cString: strerror(errno))) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let error = errno
            close(fd)
            return error == EWOULDBLOCK ? .heldElsewhere : .unavailable(String(cString: strerror(error)))
        }
        descriptor = fd
        return .acquired
    }
}
