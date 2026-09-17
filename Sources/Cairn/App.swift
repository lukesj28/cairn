import Cocoa
import SwiftUI
import Combine
import CairnKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let stackManager = StackManager()
    private var settingsWindow: NSWindow?
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
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Cairn")
        }

        buildMenu()

        stackManager.$stacks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
    }

    private func buildMenu() {
        let menu = NSMenu()
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())

        for stack in stackManager.stacks {
            let item = NSMenuItem(title: stack.name, action: #selector(openStack(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = stack
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(stackManager: stackManager)
            let hostingController = NSHostingController(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.center()
            window.contentViewController = hostingController
            window.title = "Cairn Settings"
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openStack(_ sender: NSMenuItem) {
        if let stack = sender.representedObject as? Stack {
            let owning = ScreenGeometry.owningScreen()
            WindowEngine.open(stack: stack, owningScreen: owning)
        }
    }
}
