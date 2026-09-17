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
        if let appIcon = NSImage(named: "AppIcon") ?? Bundle.module.image(forResource: "AppIcon") {
            NSApp.applicationIconImage = appIcon
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = loadMenuBarIcon()
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

    private func loadMenuBarIcon() -> NSImage? {
        let image: NSImage?
        if let named = NSImage(named: "MenuBarIcon") {
            image = named
        } else if let bundleImage = Bundle.module.image(forResource: "MenuBarIcon") {
            image = bundleImage
        } else if let url = Bundle.module.url(forResource: "cairn-icon", withExtension: "png", subdirectory: "Assets.xcassets/MenuBarIcon.imageset") ??
                            Bundle.module.url(forResource: "cairn-icon", withExtension: "png"),
                  let fileImage = NSImage(contentsOf: url) {
            image = fileImage
        } else {
            image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Cairn")
        }
        image?.size = NSSize(width: 22, height: 22)
        image?.isTemplate = true
        image?.accessibilityDescription = "Cairn"
        return image
    }
}

