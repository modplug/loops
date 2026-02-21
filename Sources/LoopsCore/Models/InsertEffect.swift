import Foundation

public struct InsertEffect: Codable, Equatable, Sendable, Identifiable {
    public var id: ID<InsertEffect>
    public var component: AudioComponentInfo
    public var displayName: String
    public var isBypassed: Bool
    public var presetData: Data?
    public var orderIndex: Int

    public init(
        id: ID<InsertEffect> = ID(),
        component: AudioComponentInfo,
        displayName: String,
        isBypassed: Bool = false,
        presetData: Data? = nil,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.component = component
        self.displayName = displayName
        self.isBypassed = isBypassed
        self.presetData = presetData
        self.orderIndex = orderIndex
    }
}
