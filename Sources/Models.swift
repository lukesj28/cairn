import Foundation

struct Stack: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var windows: [WindowSnapshot]
    var terminalCommands: [TerminalCommand]
    var browserURLs: [String]
}

struct WindowSnapshot: Codable, Identifiable {
    var id: UUID = UUID()
    var appName: String
    var bundleIdentifier: String
    var frame: CGRect
    var displayID: UInt32
}

enum TerminalTarget: String, Codable, CaseIterable {
    case appleTerminal = "Apple Terminal"
    case wezTerm = "WezTerm"
    case fallback = "Fallback (.command file)"
}

struct TerminalCommand: Codable, Identifiable {
    var id: UUID = UUID()
    var target: TerminalTarget
    var command: String
}
