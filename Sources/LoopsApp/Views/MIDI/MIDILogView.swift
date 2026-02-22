import SwiftUI
import LoopsCore
import LoopsEngine

/// Floating window manager for the MIDI log view.
@MainActor
final class MIDILogWindowManager {
    static let shared = MIDILogWindowManager()

    private var window: NSWindow?

    func toggle(monitor: MIDIActivityMonitor) {
        if let existing = window, existing.isVisible {
            existing.close()
            return
        }
        open(monitor: monitor)
    }

    func open(monitor: MIDIActivityMonitor) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostingView = NSHostingView(rootView: MIDILogView(monitor: monitor))
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "MIDI Log"
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow
    }
}

/// Scrolling table of MIDI messages with device and channel filters.
struct MIDILogView: View {
    let monitor: MIDIActivityMonitor
    @State private var deviceFilter: String? = nil
    @State private var channelFilter: UInt8? = nil
    @State private var autoScroll: Bool = true

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Button("Clear") {
                    monitor.clearLog()
                }

                Toggle("Pause", isOn: Binding(
                    get: { monitor.isPaused },
                    set: { monitor.isPaused = $0 }
                ))
                .toggleStyle(.button)

                Spacer()

                // Device filter
                Menu {
                    Button("All Devices") { deviceFilter = nil }
                    Divider()
                    ForEach(uniqueDeviceNames, id: \.self) { name in
                        Button(name) { deviceFilter = name }
                    }
                } label: {
                    Text(deviceFilter ?? "All Devices")
                        .frame(minWidth: 80)
                }

                // Channel filter
                Menu {
                    Button("All Channels") { channelFilter = nil }
                    Divider()
                    ForEach(1...16, id: \.self) { ch in
                        Button("Ch \(ch)") { channelFilter = UInt8(ch - 1) }
                    }
                } label: {
                    Text(channelFilter.map { "Ch \($0 + 1)" } ?? "All Channels")
                        .frame(minWidth: 60)
                }
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Header row
            HStack(spacing: 0) {
                Text("Time")
                    .frame(width: 80, alignment: .leading)
                Text("Device")
                    .frame(width: 140, alignment: .leading)
                Text("Ch")
                    .frame(width: 30, alignment: .leading)
                Text("Message")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredMessages) { entry in
                            HStack(spacing: 0) {
                                Text(Self.timestampFormatter.string(from: entry.timestamp))
                                    .frame(width: 80, alignment: .leading)
                                Text(entry.deviceName ?? entry.deviceID ?? "—")
                                    .frame(width: 140, alignment: .leading)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text("\(entry.channel + 1)")
                                    .frame(width: 30, alignment: .leading)
                                Text(entry.message.displayString)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .id(entry.id)
                            .background(
                                entry.id == filteredMessages.last?.id
                                    ? Color.accentColor.opacity(0.05)
                                    : Color.clear
                            )
                        }
                    }
                }
                .onChange(of: monitor.recentMessages.count) { _, _ in
                    if autoScroll, let lastID = filteredMessages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var filteredMessages: [MIDILogEntry] {
        monitor.recentMessages.filter { entry in
            if let df = deviceFilter {
                guard (entry.deviceName ?? entry.deviceID) == df else { return false }
            }
            if let cf = channelFilter {
                guard entry.channel == cf else { return false }
            }
            return true
        }
    }

    private var uniqueDeviceNames: [String] {
        let names = Set(monitor.recentMessages.compactMap { $0.deviceName ?? $0.deviceID })
        return names.sorted()
    }
}
