import Foundation
import Combine

public final class StackManager: ObservableObject {
    @Published public var stacks: [Stack] = []
    private let fileManager = FileManager.default
    private let stacksURL: URL

    public convenience init() {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        self.init(directory: paths[0].appendingPathComponent("Cairn"))
    }

    public init(directory: URL) {
        self.stacksURL = directory.appendingPathComponent("stacks.json")

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("Cairn: cannot create \(directory.path): \(error.localizedDescription)")
        }
        loadStacks()
    }

    public func loadStacks() {
        guard fileManager.fileExists(atPath: stacksURL.path) else { return }
        let decoder = JSONDecoder()
        decoder.userInfo[WindowSnapshot.visibleFrameUserInfoKey] = ScreenGeometry.activeVisibleFrame
        do {
            stacks = try decoder.decode([Stack].self, from: Data(contentsOf: stacksURL))
        } catch {
            let quarantine = stacksURL.appendingPathExtension("corrupt")
            try? fileManager.removeItem(at: quarantine)
            do {
                try fileManager.moveItem(at: stacksURL, to: quarantine)
                NSLog("Cairn: \(stacksURL.path) is unreadable (\(error.localizedDescription)); kept a copy at \(quarantine.path)")
            } catch {
                NSLog("Cairn: cannot quarantine \(stacksURL.path): \(error.localizedDescription)")
            }
        }
    }

    private func saveStacks() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            try encoder.encode(stacks).write(to: stacksURL, options: .atomic)
        } catch {
            NSLog("Cairn: cannot write \(stacksURL.path): \(error.localizedDescription)")
        }
    }

    public func addStack(_ stack: Stack) {
        stacks.append(stack)
        saveStacks()
    }

    public func updateStack(_ stack: Stack) {
        if let index = stacks.firstIndex(where: { $0.id == stack.id }) {
            stacks[index] = stack
            saveStacks()
        }
    }

    public func deleteStack(_ stack: Stack) {
        stacks.removeAll { $0.id == stack.id }
        saveStacks()
    }

    public func deleteStack(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            stacks.remove(at: index)
        }
        saveStacks()
    }
}
