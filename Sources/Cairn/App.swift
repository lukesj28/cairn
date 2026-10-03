import Cocoa
import SwiftUI
import Combine
import CairnKit
import Sparkle
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let snapshotNewStack = Self("snapshotNewStack")
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var statusItem: NSStatusItem!
    private let stackManager = StackManager()
    private var mainWindow: NSWindow?
    private let navigation = Navigation()
    private var cancellables = Set<AnyCancellable>()
    private var updaterController: SPUStandardUpdaterController!
    private var installUpdate: (() -> Void)?

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

        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)

        buildMenu()

        KeyboardShortcuts.onKeyUp(for: .snapshotNewStack) { [weak self] in
            self?.snapshotNewStack()
        }

        stackManager.$stacks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
    }

    private func buildMenu() {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open Cairn", action: #selector(showMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())

        if stackManager.stacks.isEmpty {
            let emptyItem = NSMenuItem(title: "(No Stacks Saved)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for stack in stackManager.stacks {
                let item = NSMenuItem(title: stack.name, action: #selector(openStack(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = stack
                item.toolTip = "\(stack.windows.count) window\(stack.windows.count == 1 ? "" : "s") · \(stack.screens == 1 ? "1 display" : "2 displays")"
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let snapshotItem = NSMenuItem(title: "Snapshot to New Stack", action: #selector(snapshotNewStack), keyEquivalent: "")
        snapshotItem.target = self
        menu.addItem(snapshotItem)

        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        if installUpdate != nil {
            let item = NSMenuItem(title: "Restart to Update", action: #selector(restartToUpdate), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Cairn", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func showSettings() {
        navigation.showingSettings = true
        presentWindow()
    }

    @objc private func showMainWindow() {
        navigation.showingSettings = false
        presentWindow()
    }

    private func presentWindow() {
        let window = mainWindow ?? {
            let view = MainView(stackManager: stackManager, updater: updaterController.updater, navigation: navigation)
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable],
                               backing: .buffered, defer: false)
            win.center()
            win.contentViewController = NSHostingController(rootView: view)
            win.title = "Cairn"
            win.subtitle = "Window Stacks"
            win.minSize = NSSize(width: 860, height: 560)
            win.setFrameAutosaveName("CairnMainWindow")
            win.isReleasedWhenClosed = false
            self.mainWindow = win
            return win
        }()

        if window.frame.width < 860 || window.frame.height < 560 {
            window.setContentSize(NSSize(width: max(window.frame.width, 940), height: max(window.frame.height, 620)))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc private func restartToUpdate() {
        installUpdate?()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        installUpdate = immediateInstallHandler
        buildMenu()
        return true
    }

    @objc private func snapshotNewStack() {
        WindowEngine.snapshot(screens: 1) { [weak self] windows in
            guard let self else { return }
            let name = self.stackManager.nextDefaultStackName()
            let stack = Stack(name: name, windows: windows)
            self.stackManager.addStack(stack)
            self.showMainWindow()
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

