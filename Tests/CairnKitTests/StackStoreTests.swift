import Testing
import Foundation
import CoreGraphics
@testable import CairnKit

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cairn-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

private func fixture() -> Stack {
    Stack(name: "A",
          windows: [WindowSnapshot(appName: "Zed",
                                   bundleIdentifier: "dev.zed.Zed",
                                   rect: CGRect(x: 0, y: 0, width: 0.5, height: 1),
                                   screen: 1)],
          screens: 2)
}

@Suite("Stack store")
struct StackStoreTests {
    @Test("an empty directory yields no stacks and writes nothing")
    func emptyDirectory() throws {
        try withTemporaryDirectory { dir in
            let manager = StackManager(directory: dir)
            #expect(manager.stacks.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("stacks.json").path))
        }
    }

    @Test("an added stack survives a reload")
    func addedSurvivesReload() throws {
        try withTemporaryDirectory { dir in
            let manager = StackManager(directory: dir)
            manager.addStack(fixture())

            let reloaded = StackManager(directory: dir)
            #expect(reloaded.stacks.count == 1)
            #expect(reloaded.stacks[0].id == manager.stacks[0].id)
            #expect(reloaded.stacks[0].name == "A")
            #expect(reloaded.stacks[0].screens == 2)
            #expect(reloaded.stacks[0].windows[0].screen == 1)
            #expect(isClose(reloaded.stacks[0].windows[0].rect, CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        }
    }

    @Test("an edited stack survives a reload")
    func editedSurvivesReload() throws {
        try withTemporaryDirectory { dir in
            let manager = StackManager(directory: dir)
            manager.addStack(fixture())

            var edited = manager.stacks[0]
            edited.name = "B"
            edited.windows[0].rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            manager.updateStack(edited)

            let reloaded = StackManager(directory: dir)
            #expect(reloaded.stacks.count == 1)
            #expect(reloaded.stacks[0].name == "B")
            #expect(isClose(reloaded.stacks[0].windows[0].rect, CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        }
    }

    @Test("updating an unknown stack changes nothing")
    func updateUnknownIsNoOp() throws {
        try withTemporaryDirectory { dir in
            let manager = StackManager(directory: dir)
            manager.addStack(fixture())
            let before = try Data(contentsOf: dir.appendingPathComponent("stacks.json"))

            manager.updateStack(Stack(name: "ghost", windows: []))

            let after = try Data(contentsOf: dir.appendingPathComponent("stacks.json"))
            #expect(before == after)
            #expect(manager.stacks.count == 1)
        }
    }

    @Test("a deleted stack stays deleted")
    func deletedStaysDeleted() throws {
        try withTemporaryDirectory { dir in
            let manager = StackManager(directory: dir)
            manager.addStack(fixture())
            manager.deleteStack(manager.stacks[0])

            let reloaded = StackManager(directory: dir)
            #expect(reloaded.stacks.isEmpty)
            let data = try Data(contentsOf: dir.appendingPathComponent("stacks.json"))
            let decoded = try JSONDecoder().decode([Stack].self, from: data)
            #expect(decoded.isEmpty)
        }
    }

    @Test("a legacy file is rewritten in the current format")
    func legacyFileRewritten() throws {
        try withTemporaryDirectory { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let legacyJSON = """
            [{"name":"New Stack","terminalCommands":[],"browserURLs":[],"windows":[{"frame":[[0,33],[1512,946]],"displayID":0,"bundleIdentifier":"org.mozilla.firefox","id":"27181A18-8BFB-417F-903C-694662EB0A7F","appName":"Firefox"}]}]
            """
            try legacyJSON.write(to: dir.appendingPathComponent("stacks.json"), atomically: true, encoding: .utf8)

            let manager = StackManager(directory: dir)
            #expect(manager.stacks.count == 1)
            let rect = manager.stacks[0].windows[0].rect
            #expect(rect.minX >= 0 && rect.maxX <= 1)
            #expect(rect.minY >= 0 && rect.maxY <= 1)

            manager.updateStack(manager.stacks[0])
            let rewritten = try String(contentsOf: dir.appendingPathComponent("stacks.json"), encoding: .utf8)
            #expect(rewritten.contains("\"rect\""))
            #expect(!rewritten.contains("\"frame\""))
            #expect(!rewritten.contains("\"displayID\""))
        }
    }

    @Test("an unreadable file is preserved, not overwritten")
    func unreadableFilePreserved() throws {
        try withTemporaryDirectory { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let stacksURL = dir.appendingPathComponent("stacks.json")
            try "{ not json".write(to: stacksURL, atomically: true, encoding: .utf8)

            let manager = StackManager(directory: dir)
            #expect(manager.stacks.isEmpty)
            let quarantine = dir.appendingPathComponent("stacks.json.corrupt")
            #expect(FileManager.default.fileExists(atPath: quarantine.path))
            #expect(try String(contentsOf: quarantine, encoding: .utf8) == "{ not json")

            manager.addStack(fixture())
            let reloaded = StackManager(directory: dir)
            #expect(reloaded.stacks.count == 1)
            #expect(try String(contentsOf: quarantine, encoding: .utf8) == "{ not json")
        }
    }
}
