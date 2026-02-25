import os

/// Centralized performance instrumentation for profiling and log capture.
///
/// Two output channels:
///   - **OSSignposter** → Xcode Instruments (signpost intervals & events)
///   - **Logger** → `log stream` / Console.app (filterable text messages)
///
/// Terminal usage:
///   ```
///   log stream --predicate 'subsystem == "com.loops.performance"' --level debug
///   ```
///
/// Instruments usage:
///   1. Product → Profile (Cmd+I)
///   2. Add the "os_signpost" instrument
///   3. Filter by subsystem "com.loops.performance"
public enum Signposts {
    // MARK: - Signposters (for Instruments)

    /// SwiftUI view body evaluations and layout
    public static let views = OSSignposter(subsystem: subsystem, category: "Views")

    /// Audio engine operations (start, stop, graph rebuild)
    public static let engine = OSSignposter(subsystem: subsystem, category: "AudioEngine")

    /// File I/O: audio import, project save/load, waveform generation
    public static let fileIO = OSSignposter(subsystem: subsystem, category: "FileIO")

    /// Playback scheduling and MIDI dispatch
    public static let playback = OSSignposter(subsystem: subsystem, category: "Playback")

    // MARK: - Loggers (for log stream / Console.app)

    public static let viewsLog = Logger(subsystem: subsystem, category: "Views")
    public static let engineLog = Logger(subsystem: subsystem, category: "AudioEngine")
    public static let fileIOLog = Logger(subsystem: subsystem, category: "FileIO")
    public static let playbackLog = Logger(subsystem: subsystem, category: "Playback")

    private static let subsystem = "com.loops.performance"
}
