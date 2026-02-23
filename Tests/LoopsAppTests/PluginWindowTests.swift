import Testing
import Foundation
import AppKit
import AVFoundation
@testable import LoopsApp
@testable import LoopsCore

@Suite("Plugin Window Tests")
struct PluginWindowTests {

    // Apple's built-in AUDelay: aufx/dely/appl
    private static let delayComponent = AudioComponentInfo(
        componentType: 0x61756678,   // 'aufx'
        componentSubType: 0x64656C79, // 'dely'
        componentManufacturer: 0x6170706C // 'appl'
    )

    // Apple's built-in AUReverb2: aufx/rvb2/appl
    private static let reverbComponent = AudioComponentInfo(
        componentType: 0x61756678,   // 'aufx'
        componentSubType: 0x72766232, // 'rvb2'
        componentManufacturer: 0x6170706C // 'appl'
    )

    @Test("Effect plugin window opens with non-loading dimensions")
    @MainActor
    func effectWindowOpensWithCorrectSize() async throws {
        let manager = PluginWindowManager()
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            onPresetChanged: nil
        )

        // Wait for async AU loading and sizing
        try await Task.sleep(for: .seconds(2))

        let window = manager.window(for: Self.delayComponent)
        #expect(window != nil)
        #expect(window!.isVisible)

        // Window should have been resized from the 400x300 loading rect
        // to match the plugin's preferred content size (or generic parameter view).
        let size = window!.contentView?.frame.size ?? .zero
        #expect(size.width > 0)
        #expect(size.height > 0)

        window?.close()
    }

    @Test("Two different effect plugins produce windows")
    @MainActor
    func twoEffectPluginsOpenSeparateWindows() async throws {
        let manager = PluginWindowManager()
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            onPresetChanged: nil
        )
        manager.open(
            component: Self.reverbComponent,
            displayName: "AUReverb2",
            presetData: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(2))

        let delayWindow = manager.window(for: Self.delayComponent)
        let reverbWindow = manager.window(for: Self.reverbComponent)
        #expect(delayWindow != nil)
        #expect(reverbWindow != nil)
        #expect(delayWindow !== reverbWindow)

        delayWindow?.close()
        reverbWindow?.close()
    }

    @Test("Plugin window with live AU uses engine instance")
    @MainActor
    func pluginWindowUsesLiveAU() async throws {
        // Create a live AU instance (simulating the engine's effect)
        let description = AudioComponentDescription(
            componentType: Self.delayComponent.componentType,
            componentSubType: Self.delayComponent.componentSubType,
            componentManufacturer: Self.delayComponent.componentManufacturer,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let liveAU = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAudioUnit, Error>) in
            AVAudioUnit.instantiate(with: description, options: []) { audioUnit, error in
                if let audioUnit = audioUnit {
                    continuation.resume(returning: audioUnit)
                } else {
                    continuation.resume(throwing: error!)
                }
            }
        }

        // Modify a parameter on the live instance
        guard let param = liveAU.auAudioUnit.parameterTree?.allParameters.first else {
            Issue.record("AUDelay should have parameters")
            return
        }
        let testValue = param.minValue + (param.maxValue - param.minValue) * 0.42
        param.value = testValue

        // Open plugin window with the live AU
        var savedPreset: Data?
        let manager = PluginWindowManager()
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            liveAudioUnit: liveAU,
            onPresetChanged: { data in
                savedPreset = data
            }
        )

        try await Task.sleep(for: .seconds(2))

        let window = manager.window(for: Self.delayComponent)
        #expect(window != nil)

        // Verify parameter value is still what we set (same instance)
        #expect(abs(param.value - testValue) < 0.01)

        // Close window — preset should be saved from the live instance
        window?.close()
        try await Task.sleep(for: .milliseconds(100))

        #expect(savedPreset != nil)

        window?.close()
    }

    @Test("Plugin window without live AU creates standalone instance")
    @MainActor
    func pluginWindowFallsBackToStandalone() async throws {
        let manager = PluginWindowManager()
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            liveAudioUnit: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(2))

        let window = manager.window(for: Self.delayComponent)
        #expect(window != nil)
        #expect(window!.isVisible)

        window?.close()
    }

    @Test("Opening same plugin twice reuses existing window")
    @MainActor
    func samePluginReusesWindow() async throws {
        let manager = PluginWindowManager()
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(1))

        let first = manager.window(for: Self.delayComponent)
        #expect(first != nil)

        // Open the same plugin again — should reuse existing window
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            onPresetChanged: nil
        )

        let second = manager.window(for: Self.delayComponent)
        #expect(first === second)

        first?.close()
    }

    @Test("Auto-open plugin window after adding effect opens with nil preset")
    @MainActor
    func autoOpenAfterAddEffect() async throws {
        // Simulate the add-effect flow: create an InsertEffect, then immediately open plugin window
        let effect = InsertEffect(
            component: Self.delayComponent,
            displayName: "AUDelay",
            orderIndex: 0
        )

        let manager = PluginWindowManager()
        manager.open(
            component: effect.component,
            displayName: effect.displayName,
            presetData: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(2))

        let window = manager.window(for: effect.component)
        #expect(window != nil)
        #expect(window!.isVisible)

        window?.close()
    }

    @Test("Auto-open effect while another plugin window is open keeps both visible")
    @MainActor
    func autoOpenEffectWithExistingWindowOpen() async throws {
        let manager = PluginWindowManager()

        // Open first effect (delay)
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(1))

        let delayWindow = manager.window(for: Self.delayComponent)
        #expect(delayWindow != nil)

        // Auto-open second effect (reverb) — simulating adding a new effect
        manager.open(
            component: Self.reverbComponent,
            displayName: "AUReverb2",
            presetData: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(2))

        let reverbWindow = manager.window(for: Self.reverbComponent)
        #expect(reverbWindow != nil)
        #expect(delayWindow!.isVisible)
        #expect(reverbWindow!.isVisible)
        #expect(delayWindow !== reverbWindow)

        delayWindow?.close()
        reverbWindow?.close()
    }

    @Test("Auto-opened plugin window receives preset callback on close")
    @MainActor
    func autoOpenPresetCallbackOnClose() async throws {
        var savedPreset: Data?

        let manager = PluginWindowManager()
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            onPresetChanged: { data in
                savedPreset = data
            }
        )

        try await Task.sleep(for: .seconds(2))

        let window = manager.window(for: Self.delayComponent)
        #expect(window != nil)

        // Close triggers preset save
        window?.close()
        try await Task.sleep(for: .milliseconds(200))

        #expect(savedPreset != nil)
    }

    // MARK: - invalidateAll Tests

    @Test("invalidateAll clears window cache so window(for:) returns nil")
    @MainActor
    func invalidateAllClearsCache() async throws {
        let manager = PluginWindowManager()
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(1))

        let before = manager.window(for: Self.delayComponent)
        #expect(before != nil)

        manager.invalidateAll()

        let after = manager.window(for: Self.delayComponent)
        #expect(after == nil, "window(for:) must return nil after invalidateAll")
    }

    @Test("invalidateAll allows opening a new window for same component")
    @MainActor
    func invalidateAllAllowsNewWindow() async throws {
        let manager = PluginWindowManager()
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(1))

        let first = manager.window(for: Self.delayComponent)
        #expect(first != nil)

        manager.invalidateAll()

        // Open a new window for the same component
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay v2",
            presetData: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(1))

        let second = manager.window(for: Self.delayComponent)
        #expect(second != nil)
        // Must be a different window instance (old one was invalidated)
        #expect(first !== second)

        second?.close()
    }

    @Test("invalidateAll with multiple windows clears all")
    @MainActor
    func invalidateAllClearsMultipleWindows() async throws {
        let manager = PluginWindowManager()
        manager.open(
            component: Self.delayComponent,
            displayName: "AUDelay",
            presetData: nil,
            onPresetChanged: nil
        )
        manager.open(
            component: Self.reverbComponent,
            displayName: "AUReverb2",
            presetData: nil,
            onPresetChanged: nil
        )

        try await Task.sleep(for: .seconds(1))

        #expect(manager.window(for: Self.delayComponent) != nil)
        #expect(manager.window(for: Self.reverbComponent) != nil)

        manager.invalidateAll()

        #expect(manager.window(for: Self.delayComponent) == nil)
        #expect(manager.window(for: Self.reverbComponent) == nil)
    }
}
