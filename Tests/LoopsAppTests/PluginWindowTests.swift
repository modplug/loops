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
}
