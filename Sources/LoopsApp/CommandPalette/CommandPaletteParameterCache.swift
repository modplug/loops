import Foundation
import LoopsCore
import LoopsEngine

extension Notification.Name {
    static let loopsCommandPaletteParametersDidChange = Notification.Name("loops.commandPaletteParametersDidChange")
}

@MainActor
public final class CommandPaletteParameterCache {
    public static let shared = CommandPaletteParameterCache()

    private enum Entry {
        case loading(Task<Void, Never>)
        case loaded([AudioUnitParameterInfo])
    }

    private let provider: (AudioComponentInfo) async -> [AudioUnitParameterInfo]
    private var entries: [AudioComponentInfo: Entry] = [:]

    public init(provider: @escaping (AudioComponentInfo) async -> [AudioUnitParameterInfo] = { component in
        let discovery = AudioUnitDiscovery()
        return await discovery.parameters(for: component)
    }) {
        self.provider = provider
    }

    public func parameters(for component: AudioComponentInfo) -> [AudioUnitParameterInfo]? {
        guard case .loaded(let parameters) = entries[component] else {
            return nil
        }
        return parameters
    }

    public func isLoading(component: AudioComponentInfo) -> Bool {
        if case .loading = entries[component] {
            return true
        }
        return false
    }

    public func ensureLoaded(component: AudioComponentInfo) {
        guard entries[component] == nil else { return }

        let task = Task { [weak self] in
            let parameters = await self?.provider(component) ?? []
            await MainActor.run {
                self?.entries[component] = .loaded(parameters)
                NotificationCenter.default.post(name: .loopsCommandPaletteParametersDidChange, object: component)
            }
        }

        entries[component] = .loading(task)
    }

    public func prime(component: AudioComponentInfo, parameters: [AudioUnitParameterInfo]) {
        if case .loading(let task) = entries[component] {
            task.cancel()
        }
        entries[component] = .loaded(parameters)
        NotificationCenter.default.post(name: .loopsCommandPaletteParametersDidChange, object: component)
    }
}
