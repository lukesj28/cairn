import Foundation

public struct Stack: Codable, Identifiable {
    public var id: UUID = UUID()
    public var name: String
    public var windows: [WindowSnapshot]
    public var screens: Int = 1

    enum CodingKeys: String, CodingKey { case id, name, windows, screens }

    public init(id: UUID = UUID(), name: String, windows: [WindowSnapshot], screens: Int = 1) {
        self.id = id
        self.name = name
        self.windows = windows
        self.screens = screens
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        windows = try c.decode([WindowSnapshot].self, forKey: .windows)
        screens = min(max(1, try c.decodeIfPresent(Int.self, forKey: .screens) ?? 1), 2)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(windows, forKey: .windows)
        try c.encode(screens, forKey: .screens)
    }
}

public struct WindowSnapshot: Codable, Identifiable {
    public var id: UUID = UUID()
    public var appName: String
    public var bundleIdentifier: String
    public var rect: CGRect
    public var screen: Int = 0

    enum CodingKeys: String, CodingKey { case id, appName, bundleIdentifier, rect, screen }
    private enum LegacyKeys: String, CodingKey { case frame }
    public static let visibleFrameUserInfoKey = CodingUserInfoKey(rawValue: "cairn.visibleFrame")!

    public init(id: UUID = UUID(), appName: String, bundleIdentifier: String, rect: CGRect, screen: Int = 0) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.rect = rect
        self.screen = screen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        appName = try c.decode(String.self, forKey: .appName)
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        screen = max(0, try c.decodeIfPresent(Int.self, forKey: .screen) ?? 0)
        if let r = try c.decodeIfPresent(CGRect.self, forKey: .rect) {
            rect = ScreenGeometry.clamp(r)
        } else {
            let visible = decoder.userInfo[WindowSnapshot.visibleFrameUserInfoKey] as? CGRect
                ?? ScreenGeometry.activeVisibleFrame
            let legacy = try decoder.container(keyedBy: LegacyKeys.self).decode(CGRect.self, forKey: .frame)
            rect = ScreenGeometry.fraction(ofAX: legacy, in: visible)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(appName, forKey: .appName)
        try c.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try c.encode(rect, forKey: .rect)
        try c.encode(screen, forKey: .screen)
    }
}
