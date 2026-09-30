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

        if stackManager.stacks.isEmpty {
            let emptyItem = NSMenuItem(title: "(No Stacks Saved)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (idx, stack) in stackManager.stacks.enumerated() {
                let keyEq = idx < 9 ? "\(idx + 1)" : ""
                let item = NSMenuItem(title: stack.name, action: #selector(openStack(_:)), keyEquivalent: keyEq)
                item.target = self
                item.representedObject = stack
                item.toolTip = "\(stack.windows.count) window\(stack.windows.count == 1 ? "" : "s") · \(stack.screens == 1 ? "1 display" : "2 displays")"
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let snapshotItem = NSMenuItem(title: "Snapshot Current Windows as New Stack...", action: #selector(snapshotNewStack), keyEquivalent: "s")
        snapshotItem.keyEquivalentModifierMask = [.command, .shift]
        snapshotItem.target = self
        menu.addItem(snapshotItem)

        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Cairn", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(stackManager: stackManager)
            let hostingController = NSHostingController(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.center()
            window.contentViewController = hostingController
            window.title = "Cairn"
            window.subtitle = "Window Stacks"
            window.minSize = NSSize(width: 860, height: 560)
            window.setFrameAutosaveName("CairnMainWindow")
            window.isReleasedWhenClosed = false
            self.settingsWindow = window
        }
        if let win = settingsWindow, win.frame.width < 860 || win.frame.height < 560 {
            win.setContentSize(NSSize(width: max(win.frame.width, 940), height: max(win.frame.height, 620)))
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func snapshotNewStack() {
        WindowEngine.snapshot(screens: 1) { [weak self] windows in
            guard let self else { return }
            let count = self.stackManager.stacks.count + 1
            let stack = Stack(name: "Stack \(count)", windows: windows)
            self.stackManager.addStack(stack)
            self.showSettings()
        }
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
        } else {
            image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Cairn")
        }
        image?.size = NSSize(width: 22, height: 22)
        image?.isTemplate = true
        image?.accessibilityDescription = "Cairn"
        return image
    }
}

