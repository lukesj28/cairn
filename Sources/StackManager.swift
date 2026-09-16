import Foundation
import Combine

class StackManager: ObservableObject {
    @Published var stacks: [Stack] = []
    private let fileManager = FileManager.default
    private let stacksURL: URL

    init() {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = paths[0].appendingPathComponent("Cairn")
        self.stacksURL = appSupportURL.appendingPathComponent("stacks.json")

        try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        loadStacks()
    }

    func loadStacks() {
        guard let data = try? Data(contentsOf: stacksURL) else { return }
        let decoder = JSONDecoder()
        if let loaded = try? decoder.decode([Stack].self, from: data) {
            DispatchQueue.main.async {
                self.stacks = loaded
            }
        }
    }

    func saveStacks() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(stacks) {
            try? data.write(to: stacksURL)
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
