import Foundation

/// Identifies which fields of a Container have been locally overridden
/// on a linked clone. Non-overridden fields inherit from the parent container.
public enum ContainerField: String, Codable, Equatable, Sendable, CaseIterable, Hashable {
    case effects
    case automation
    case fades
    case enterActions
    case exitActions
    case name
    case loopSettings
    case instrumentOverride

    public var displayName: String {
        switch self {
        case .effects: return "Effects"
        case .automation: return "Automation"
        case .fades: return "Fades"
        case .enterActions: return "Enter Actions"
        case .exitActions: return "Exit Actions"
        case .name: return "Name"
        case .loopSettings: return "Loop Settings"
        case .instrumentOverride: return "Instrument"
        }
    }
}
