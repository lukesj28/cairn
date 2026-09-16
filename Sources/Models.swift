import Foundation

struct Stack: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var windows: [WindowSnapshot]
    var screens: Int = 1

    enum CodingKeys: String, CodingKey { case id, name, windows, screens }

    init(id: UUID = UUID(), name: String, windows: [WindowSnapshot], screens: Int = 1) {
        self.id = id
        self.name = name
        self.windows = windows
        self.screens = screens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        windows = try c.decode([WindowSnapshot].self, forKey: .windows)
        screens = try c.decodeIfPresent(Int.self, forKey: .screens) ?? 1
    }
}

struct WindowSnapshot: Codable, Identifiable {
    var id: UUID = UUID()
    var appName: String
    var bundleIdentifier: String
    var rect: CGRect
    var screen: Int = 0

    enum CodingKeys: String, CodingKey { case id, appName, bundleIdentifier, rect, screen }
    private enum LegacyKeys: String, CodingKey { case frame }

    init(id: UUID = UUID(), appName: String, bundleIdentifier: String, rect: CGRect, screen: Int = 0) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.rect = rect
        self.screen = screen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        appName = try c.decode(String.self, forKey: .appName)
        bundleIdentifier = try c.decode(String.self, forKey: .bundleIdentifier)
        screen = try c.decodeIfPresent(Int.self, forKey: .screen) ?? 0
        if let r = try c.decodeIfPresent(CGRect.self, forKey: .rect) {
            rect = r
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self).decode(CGRect.self, forKey: .frame)
            rect = ScreenGeometry.fraction(ofAX: legacy, in: ScreenGeometry.activeVisibleFrame)
        }
    }
}
