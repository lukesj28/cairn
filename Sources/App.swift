import Cocoa
import SwiftUI
import Combine

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var profileManager = ProfileManager()
    var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "LayoutManager")
        }

        buildMenu()

        // Rebuild menu when profiles change
        profileManager.$profiles
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
    }

    func buildMenu() {
        let menu = NSMenu()
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let snapshotItem = NSMenuItem(title: "Snapshot Current Layout", action: #selector(snapshotLayout), keyEquivalent: "s")
        snapshotItem.target = self
        menu.addItem(snapshotItem)
        
        menu.addItem(NSMenuItem.separator())

        for profile in profileManager.profiles {
            let item = NSMenuItem(title: "Restore: \(profile.name)", action: #selector(restoreProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(profileManager: profileManager)
            let hostingController = NSHostingController(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.center()
            window.contentViewController = hostingController
            window.title = "LayoutManager Settings"
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func snapshotLayout() {
        let windows = WindowEngine.snapshot()
        let name = "Snapshot \(Date().formatted(date: .abbreviated, time: .shortened))"
        let newProfile = Profile(name: name, windows: windows, terminalCommands: [], browserURLs: [])
        profileManager.addProfile(newProfile)
    }

    @objc func restoreProfile(_ sender: NSMenuItem) {
        if let profile = sender.representedObject as? Profile {
            WindowEngine.restore(profile: profile)

            // Execute terminal commands
            TerminalAdapter.execute(commands: profile.terminalCommands)

            // Launch browsers
            for urlString in profile.browserURLs {
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
