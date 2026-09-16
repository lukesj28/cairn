import Foundation
import Combine

final class StackManager: ObservableObject {
    @Published var stacks: [Stack] = []
    private let fileManager = FileManager.default
    private let stacksURL: URL

    init() {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = paths[0].appendingPathComponent("Cairn")
        self.stacksURL = appSupportURL.appendingPathComponent("stacks.json")

        do {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        } catch {
            NSLog("Cairn: cannot create \(appSupportURL.path): \(error.localizedDescription)")
        }
        loadStacks()
    }

    func loadStacks() {
        guard fileManager.fileExists(atPath: stacksURL.path) else { return }
        do {
            stacks = try JSONDecoder().decode([Stack].self, from: Data(contentsOf: stacksURL))
        } catch {
            NSLog("Cairn: cannot read \(stacksURL.path): \(error.localizedDescription)")
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

    func addStack(_ stack: Stack) {
        stacks.append(stack)
        saveStacks()
    }

    func updateStack(_ stack: Stack) {
        if let index = stacks.firstIndex(where: { $0.id == stack.id }) {
            stacks[index] = stack
            saveStacks()
        }
    }

    func deleteStack(_ stack: Stack) {
        stacks.removeAll { $0.id == stack.id }
        saveStacks()
    }

    func deleteStack(at offsets: IndexSet) {
        stacks.remove(atOffsets: offsets)
        saveStacks()
    }
}
