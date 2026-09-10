import OSLog

/// Structured logging. Never called from inside the event callback's hot path —
/// see `EventTapController` for why per-event logging is compiled out.
public enum Log {
    private static let subsystem = "engineer.riteshrana.scrollwise"

    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let tap = Logger(subsystem: subsystem, category: "eventtap")
    public static let permission = Logger(subsystem: subsystem, category: "permission")
    public static let devices = Logger(subsystem: subsystem, category: "devices")
    public static let settings = Logger(subsystem: subsystem, category: "settings")
    public static let login = Logger(subsystem: subsystem, category: "launchatlogin")
}
