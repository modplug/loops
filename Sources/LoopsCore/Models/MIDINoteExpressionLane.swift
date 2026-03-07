import Foundation

public enum MIDINoteExpressionLane: String, CaseIterable, Sendable, Equatable {
    case velocity
    case channel
    case sustain
    case expression

    public var label: String {
        switch self {
        case .velocity:
            return "Velocity"
        case .channel:
            return "Channel"
        case .sustain:
            return "Sustain"
        case .expression:
            return "Expression"
        }
    }

    public var shortLabel: String {
        switch self {
        case .velocity:
            return "Vel"
        case .channel:
            return "Ch"
        case .sustain:
            return "Sus"
        case .expression:
            return "Expr"
        }
    }

    public var iconName: String {
        switch self {
        case .velocity:
            return "slider.vertical.3"
        case .channel:
            return "number"
        case .sustain:
            return "pianokeys.inverse"
        case .expression:
            return "waveform.path.ecg"
        }
    }

    public var controllerNumber: UInt8? {
        switch self {
        case .velocity, .channel:
            return nil
        case .sustain:
            return 64
        case .expression:
            return 11
        }
    }

    public var isControllerLane: Bool {
        controllerNumber != nil
    }
}
