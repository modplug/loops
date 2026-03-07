import Foundation

public enum MIDITool: String, CaseIterable, Sendable, Equatable {
    case pointer
    case pencil

    public var iconName: String {
        switch self {
        case .pointer:
            return "cursorarrow"
        case .pencil:
            return "pencil.tip"
        }
    }

    public var label: String {
        switch self {
        case .pointer:
            return "Pointer"
        case .pencil:
            return "Pencil"
        }
    }
}
