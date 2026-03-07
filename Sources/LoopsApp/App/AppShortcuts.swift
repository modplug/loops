import SwiftUI
import AppKit

public enum AppShortcutCategory: String, CaseIterable, Identifiable, Sendable {
    case file
    case create
    case edit
    case navigate
    case view
    case app

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .file: return "File"
        case .create: return "Create"
        case .edit: return "Edit"
        case .navigate: return "Navigate"
        case .view: return "View"
        case .app: return "App"
        }
    }
}

public struct AppShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = AppShortcutModifiers(rawValue: 1 << 0)
    public static let shift = AppShortcutModifiers(rawValue: 1 << 1)
    public static let option = AppShortcutModifiers(rawValue: 1 << 2)
    public static let control = AppShortcutModifiers(rawValue: 1 << 3)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(Int.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct AppKeyboardShortcut: Codable, Hashable, Sendable {
    public let key: String
    public let modifiers: AppShortcutModifiers

    public init(key: String, modifiers: AppShortcutModifiers) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    public init?(event: NSEvent) {
        let modifiers = AppShortcutModifiers(eventModifiers: event.modifierFlags)
        let specialKey = Self.specialKey(for: event.keyCode)

        if specialKey == nil && modifiers.isEmpty {
            return nil
        }

        if let specialKey {
            self.init(key: specialKey, modifiers: modifiers)
            return
        }

        guard let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            characters.count == 1,
            Character(characters).isLetter || Character(characters).isNumber || Self.allowedPunctuation.contains(Character(characters))
        else {
            return nil
        }

        self.init(key: characters, modifiers: modifiers)
    }

    public var keyEquivalent: KeyEquivalent {
        switch key {
        case "space": return .space
        case "tab": return .tab
        case "return": return .return
        case "escape": return .escape
        case "delete": return .delete
        case "uparrow": return .upArrow
        case "downarrow": return .downArrow
        case "leftarrow": return .leftArrow
        case "rightarrow": return .rightArrow
        default: return KeyEquivalent(Character(key))
        }
    }

    public var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if self.modifiers.contains(.command) { modifiers.insert(.command) }
        if self.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if self.modifiers.contains(.option) { modifiers.insert(.option) }
        if self.modifiers.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    public var displayString: String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option) { parts += "⌥" }
        if modifiers.contains(.shift) { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        parts += Self.displayKey(for: key)
        return parts
    }

    private static let allowedPunctuation: Set<Character> = [",", ".", "/", ";", "'", "[", "]", "-", "="]

    private static func specialKey(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36, 76: return "return"
        case 48: return "tab"
        case 49: return "space"
        case 51, 117: return "delete"
        case 53: return "escape"
        case 123: return "leftarrow"
        case 124: return "rightarrow"
        case 125: return "downarrow"
        case 126: return "uparrow"
        default: return nil
        }
    }

    private static func displayKey(for key: String) -> String {
        switch key {
        case "space": return "Space"
        case "tab": return "⇥"
        case "return": return "↩"
        case "escape": return "⎋"
        case "delete": return "⌫"
        case "uparrow": return "↑"
        case "downarrow": return "↓"
        case "leftarrow": return "←"
        case "rightarrow": return "→"
        default: return key.uppercased()
        }
    }
}

extension AppShortcutModifiers {
    fileprivate init(eventModifiers: NSEvent.ModifierFlags) {
        var modifiers: AppShortcutModifiers = []
        if eventModifiers.contains(.command) { modifiers.insert(.command) }
        if eventModifiers.contains(.shift) { modifiers.insert(.shift) }
        if eventModifiers.contains(.option) { modifiers.insert(.option) }
        if eventModifiers.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
}

public enum AppShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case newProject
    case openProject
    case saveProject
    case saveProjectAs
    case exportAudio
    case addSong
    case addTrack
    case undo
    case redo
    case undoHistory
    case findEverything
    case openMixer
    case openSetlists
    case goToCurrentSong
    case toggleContainerArm
    case openSettings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .newProject: return "New Project"
        case .openProject: return "Open Project"
        case .saveProject: return "Save Project"
        case .saveProjectAs: return "Save Project As"
        case .exportAudio: return "Export Audio"
        case .addSong: return "Add Song"
        case .addTrack: return "Add Track"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .undoHistory: return "Undo History"
        case .findEverything: return "Find Everything"
        case .openMixer: return "Open Mixer"
        case .openSetlists: return "Open Setlists"
        case .goToCurrentSong: return "Go to Current Song"
        case .toggleContainerArm: return "Toggle Container Arm"
        case .openSettings: return "Open Settings"
        }
    }

    public var category: AppShortcutCategory {
        switch self {
        case .newProject, .openProject, .saveProject, .saveProjectAs, .exportAudio:
            return .file
        case .addSong, .addTrack:
            return .create
        case .undo, .redo, .undoHistory, .toggleContainerArm:
            return .edit
        case .findEverything, .openSetlists, .goToCurrentSong:
            return .navigate
        case .openMixer:
            return .view
        case .openSettings:
            return .app
        }
    }

    public var defaultShortcut: AppKeyboardShortcut? {
        switch self {
        case .newProject:
            return AppKeyboardShortcut(key: "n", modifiers: [.command])
        case .openProject:
            return AppKeyboardShortcut(key: "o", modifiers: [.command])
        case .saveProject:
            return AppKeyboardShortcut(key: "s", modifiers: [.command])
        case .saveProjectAs:
            return AppKeyboardShortcut(key: "s", modifiers: [.command, .shift])
        case .exportAudio:
            return AppKeyboardShortcut(key: "e", modifiers: [.command, .shift])
        case .addSong:
            return AppKeyboardShortcut(key: "n", modifiers: [.command, .option])
        case .addTrack:
            return AppKeyboardShortcut(key: "t", modifiers: [.command, .option])
        case .undo:
            return AppKeyboardShortcut(key: "z", modifiers: [.command])
        case .redo:
            return AppKeyboardShortcut(key: "z", modifiers: [.command, .shift])
        case .undoHistory:
            return nil
        case .findEverything:
            return AppKeyboardShortcut(key: "k", modifiers: [.command])
        case .openMixer:
            return nil
        case .openSetlists:
            return nil
        case .goToCurrentSong:
            return nil
        case .toggleContainerArm:
            return AppKeyboardShortcut(key: "r", modifiers: [.option])
        case .openSettings:
            return AppKeyboardShortcut(key: ",", modifiers: [.command])
        }
    }

    public var paletteNodeID: String? {
        switch self {
        case .addSong: return "global-add-song"
        case .addTrack: return "global-add-track"
        case .undo: return "global-undo"
        case .redo: return "global-redo"
        case .undoHistory: return "global-undo-history"
        case .openMixer: return "global-open-mixer"
        case .openSetlists: return "global-open-setlists"
        case .goToCurrentSong: return "global-open-current-song"
        case .openSettings: return "global-open-settings"
        default: return nil
        }
    }
}

@MainActor
@Observable
public final class ShortcutManager {
    private static let defaultsKey = "loops.app.shortcuts"
    private enum StoredShortcut: Codable, Sendable {
        case custom(AppKeyboardShortcut)
        case disabled
    }

    private var storedShortcuts: [AppShortcutAction: StoredShortcut]

    public init(userDefaults: UserDefaults = .standard) {
        if let data = userDefaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([AppShortcutAction: StoredShortcut].self, from: data) {
            storedShortcuts = decoded
        } else {
            storedShortcuts = [:]
        }
        self.userDefaults = userDefaults
    }

    private let userDefaults: UserDefaults

    public func shortcut(for action: AppShortcutAction) -> AppKeyboardShortcut? {
        switch storedShortcuts[action] {
        case .custom(let shortcut):
            return shortcut
        case .disabled:
            return nil
        case nil:
            return action.defaultShortcut
        }
    }

    @discardableResult
    public func setShortcut(_ shortcut: AppKeyboardShortcut?, for action: AppShortcutAction) -> AppShortcutAction? {
        var conflictingAction: AppShortcutAction?

        if let shortcut {
            for otherAction in AppShortcutAction.allCases where otherAction != action {
                if self.shortcut(for: otherAction) == shortcut {
                    storedShortcuts[otherAction] = .disabled
                    conflictingAction = otherAction
                }
            }
            if shortcut == action.defaultShortcut {
                storedShortcuts.removeValue(forKey: action)
            } else {
                storedShortcuts[action] = .custom(shortcut)
            }
        } else {
            storedShortcuts[action] = .disabled
        }

        persist()
        return conflictingAction
    }

    public func reset(_ action: AppShortcutAction) {
        storedShortcuts.removeValue(forKey: action)
        persist()
    }

    public func displayString(for action: AppShortcutAction) -> String? {
        shortcut(for: action)?.displayString
    }

    public func actions(in category: AppShortcutCategory) -> [AppShortcutAction] {
        AppShortcutAction.allCases.filter { $0.category == category }
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(storedShortcuts) {
            userDefaults.set(encoded, forKey: Self.defaultsKey)
        }
    }
}

public extension View {
    @ViewBuilder
    func appKeyboardShortcut(_ shortcut: AppKeyboardShortcut?) -> some View {
        if let shortcut {
            self.keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.eventModifiers)
        } else {
            self
        }
    }
}
