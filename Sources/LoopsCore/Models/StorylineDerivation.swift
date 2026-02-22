import Foundation

/// Summary of a single container's activity within a section.
public struct ContainerActivitySummary: Equatable, Sendable {
    public let containerName: String
    public let isRecordArmed: Bool
    public let enterActionDescriptions: [String]
    public let exitActionDescriptions: [String]
    public let effectNames: [String]
    public let automationLaneCount: Int

    public init(
        containerName: String,
        isRecordArmed: Bool,
        enterActionDescriptions: [String],
        exitActionDescriptions: [String],
        effectNames: [String],
        automationLaneCount: Int
    ) {
        self.containerName = containerName
        self.isRecordArmed = isRecordArmed
        self.enterActionDescriptions = enterActionDescriptions
        self.exitActionDescriptions = exitActionDescriptions
        self.effectNames = effectNames
        self.automationLaneCount = automationLaneCount
    }
}

/// Summary of a track's activity within a section.
public struct TrackActivitySummary: Equatable, Sendable {
    public let trackID: ID<Track>
    public let trackName: String
    public let trackKind: TrackKind
    public let isRecordArmed: Bool
    public let containers: [ContainerActivitySummary]

    public init(
        trackID: ID<Track>,
        trackName: String,
        trackKind: TrackKind,
        isRecordArmed: Bool,
        containers: [ContainerActivitySummary]
    ) {
        self.trackID = trackID
        self.trackName = trackName
        self.trackKind = trackKind
        self.isRecordArmed = isRecordArmed
        self.containers = containers
    }
}

/// A single entry in the storyline: one section with aggregated track activity.
public struct StorylineEntry: Equatable, Sendable {
    public let section: SectionRegion
    public let trackSummaries: [TrackActivitySummary]

    public init(section: SectionRegion, trackSummaries: [TrackActivitySummary]) {
        self.section = section
        self.trackSummaries = trackSummaries
    }

    /// Human-readable one-line summary for this section.
    public var summary: String {
        let parts = trackSummaries.compactMap { trackSummary -> String? in
            var descriptions: [String] = []
            if trackSummary.isRecordArmed {
                descriptions.append("record armed")
            }
            for container in trackSummary.containers {
                if !container.enterActionDescriptions.isEmpty {
                    descriptions.append(contentsOf: container.enterActionDescriptions.map { "\($0) on enter" })
                }
                if !container.exitActionDescriptions.isEmpty {
                    descriptions.append(contentsOf: container.exitActionDescriptions.map { "\($0) on exit" })
                }
                if descriptions.isEmpty {
                    descriptions.append("\(container.containerName) playing")
                }
            }
            guard !descriptions.isEmpty else { return nil }
            return "\(trackSummary.trackName): \(descriptions.joined(separator: ", "))"
        }
        return parts.isEmpty ? "Empty" : parts.joined(separator: "; ")
    }
}

/// Pure derivation of storyline entries from song data.
public enum StorylineDerivation {

    /// Derives a storyline from sections and tracks, sorted by startBar.
    public static func derive(sections: [SectionRegion], tracks: [Track]) -> [StorylineEntry] {
        let sorted = sections.sorted { $0.startBar < $1.startBar }
        return sorted.map { section in
            let trackSummaries = tracks.compactMap { track -> TrackActivitySummary? in
                let activeContainers = track.containers.filter { container in
                    containersOverlap(
                        containerStart: container.startBar,
                        containerEnd: container.endBar,
                        sectionStart: section.startBar,
                        sectionEnd: section.endBar
                    )
                }
                guard !activeContainers.isEmpty || track.isRecordArmed else { return nil }
                let containerSummaries = activeContainers.map { container in
                    ContainerActivitySummary(
                        containerName: container.name,
                        isRecordArmed: container.isRecordArmed,
                        enterActionDescriptions: container.onEnterActions.map { describeAction($0) },
                        exitActionDescriptions: container.onExitActions.map { describeAction($0) },
                        effectNames: container.insertEffects.map(\.displayName),
                        automationLaneCount: container.automationLanes.count
                    )
                }
                return TrackActivitySummary(
                    trackID: track.id,
                    trackName: track.name,
                    trackKind: track.kind,
                    isRecordArmed: track.isRecordArmed,
                    containers: containerSummaries
                )
            }
            return StorylineEntry(section: section, trackSummaries: trackSummaries)
        }
    }

    private static func containersOverlap(
        containerStart: Int, containerEnd: Int,
        sectionStart: Int, sectionEnd: Int
    ) -> Bool {
        containerStart < sectionEnd && containerEnd > sectionStart
    }

    private static func describeAction(_ action: ContainerAction) -> String {
        switch action {
        case .sendMIDI(_, let message, _):
            switch message {
            case .programChange(let channel, let program):
                return "PC #\(program) ch \(channel + 1)"
            case .controlChange(let channel, let controller, let value):
                return "CC #\(controller)=\(value) ch \(channel + 1)"
            case .noteOn(let channel, let note, let velocity):
                return "Note On \(note) vel \(velocity) ch \(channel + 1)"
            case .noteOff(let channel, let note, _):
                return "Note Off \(note) ch \(channel + 1)"
            }
        case .triggerContainer(_, _, let triggerAction):
            switch triggerAction {
            case .start: return "Trigger Start"
            case .stop: return "Trigger Stop"
            case .armRecord: return "Trigger Arm"
            case .disarmRecord: return "Trigger Disarm"
            }
        case .setParameter(_, let target, let value):
            return "Set FX\(target.effectIndex) param to \(String(format: "%.1f", value))"
        }
    }
}
