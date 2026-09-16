import Cocoa

class TerminalAdapter {
    static func execute(commands: [TerminalCommand]) {
        for cmd in commands {
            switch cmd.target {
            case .appleTerminal:
                executeAppleTerminal(cmd.command)
            case .wezTerm:
                executeWezTerm(cmd.command)
            case .fallback:
                executeFallback(cmd.command)
            }
        }
    }

    private static func executeAppleTerminal(_ command: String) {
        let escapedCommand = command.replacingOccurrences(of: "\"", with: "\\\"")
        let scriptSource = """
        tell application "Terminal"
            do script "\(escapedCommand)"
            activate
        end tell
        """
        if let script = NSAppleScript(source: scriptSource) {
            var errorInfo: NSDictionary?
            script.executeAndReturnError(&errorInfo)
        }
    }

    private static func executeWezTerm(_ command: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/Applications/WezTerm.app/Contents/MacOS/wezterm")
        task.arguments = ["cli", "spawn", "--", "/bin/bash", "-c", command]
        try? task.run()
    }

    private static func executeFallback(_ command: String) {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("cairn_cmd_\(UUID().uuidString).command")

        let scriptContent = """
        #!/bin/bash
        \(command)
        """

        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            var attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
            let currentPosix = attributes[.posixPermissions] as? NSNumber ?? 0
            let newPosix = currentPosix.int16Value | 0o111
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: newPosix)], ofItemAtPath: scriptURL.path)

            NSWorkspace.shared.open(scriptURL)
        } catch {
            print("Failed to execute fallback command: \(error)")
        }
    }
}
