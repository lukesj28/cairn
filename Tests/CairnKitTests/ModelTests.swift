import Testing
import Foundation
import CoreGraphics
@testable import CairnKit

private func decodeStacks(_ json: String, visible: CGRect = laptopVisible) throws -> [Stack] {
    let decoder = JSONDecoder()
    decoder.userInfo[WindowSnapshot.visibleFrameUserInfoKey] = visible
    return try decoder.decode([Stack].self, from: Data(json.utf8))
}

@Suite("Stack persistence format")
struct ModelTests {
    @Test("a legacy stack migrates to exact fractions")
    func legacyMigration() throws {
        let json = """
        [{"name":"New Stack","terminalCommands":[],"browserURLs":[],"windows":[{"frame":[[0,33],[1512,946]],"displayID":0,"bundleIdentifier":"org.mozilla.firefox","id":"27181A18-8BFB-417F-903C-694662EB0A7F","appName":"Firefox"}]}]
        """
        let stacks = try decodeStacks(json)
        #expect(stacks.count == 1)
        #expect(stacks[0].name == "New Stack")
        #expect(stacks[0].screens == 1)
        #expect(stacks[0].windows.count == 1)
        let window = stacks[0].windows[0]
        #expect(window.id == UUID(uuidString: "27181A18-8BFB-417F-903C-694662EB0A7F"))
        #expect(window.appName == "Firefox")
        #expect(window.screen == 0)
        #expect(isClose(window.rect, CGRect(x: 0, y: 0, width: 1, height: 946.0 / 949.0)))
    }

    @Test("keys from removed features are ignored")
    func removedKeysIgnored() throws {
        let json = """
        [{"name":"New Stack","terminalCommands":[],"browserURLs":[],"windows":[{"frame":[[0,33],[1512,946]],"displayID":0,"bundleIdentifier":"org.mozilla.firefox","id":"27181A18-8BFB-417F-903C-694662EB0A7F","appName":"Firefox"}]}]
        """
        #expect(throws: Never.self) { try decodeStacks(json) }
    }

    @Test("the current format decodes verbatim")
    func currentFormatVerbatim() throws {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"Two","screens":2,"windows":[{"id":"22222222-2222-2222-2222-222222222222","appName":"Zed","bundleIdentifier":"dev.zed.Zed","rect":[[0.5,0],[0.5,1]],"screen":1}]}]
        """
        let stacks = try decodeStacks(json)
        #expect(stacks[0].id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(stacks[0].screens == 2)
        #expect(stacks[0].windows[0].id == UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        #expect(stacks[0].windows[0].screen == 1)
        #expect(isClose(stacks[0].windows[0].rect, CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
    }

    @Test("out-of-range screen values are normalised on load", arguments: [
        (screens: "0", screen: "0", expectedScreens: 1, expectedScreen: 0),
        (screens: "7", screen: "3", expectedScreens: 2, expectedScreen: 3),
        (screens: nil, screen: "-3", expectedScreens: 1, expectedScreen: 0),
        (screens: "2", screen: "1", expectedScreens: 2, expectedScreen: 1),
    ] as [(screens: String?, screen: String, expectedScreens: Int, expectedScreen: Int)])
    func outOfRangeScreens(_ input: (screens: String?, screen: String, expectedScreens: Int, expectedScreen: Int)) throws {
        let screensField = input.screens.map { "\"screens\":\($0)," } ?? ""
        let json = """
        [{"name":"X",\(screensField)"windows":[{"appName":"A","bundleIdentifier":"b","rect":[[0,0],[1,1]],"screen":\(input.screen)}]}]
        """
        let stacks = try decodeStacks(json)
        #expect(stacks[0].screens == input.expectedScreens)
        #expect(stacks[0].windows[0].screen == input.expectedScreen)
    }

    @Test("a stored rect outside 0...1 is repaired on load")
    func outOfRangeRect() throws {
        let json = """
        [{"name":"X","windows":[{"appName":"A","bundleIdentifier":"b","rect":[[0.2,0.2],[2,3]]}]}]
        """
        let stacks = try decodeStacks(json)
        #expect(isClose(stacks[0].windows[0].rect, CGRect(x: 0, y: 0, width: 1, height: 1)))
    }

    @Test("only the current keys are written")
    func onlyCurrentKeysWritten() throws {
        let stack = Stack(name: "S",
                          windows: [WindowSnapshot(appName: "A", bundleIdentifier: "b",
                                                   rect: CGRect(x: 0, y: 0, width: 0.5, height: 1), screen: 1)],
                          screens: 2)
        let data = try JSONEncoder().encode(stack)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "name", "windows", "screens"])
        let windows = try #require(object["windows"] as? [[String: Any]])
        #expect(Set(windows[0].keys) == ["id", "appName", "bundleIdentifier", "rect", "screen"])
    }

    @Test("a stack round trips through JSON")
    func roundTrip() throws {
        let stack = Stack(name: "S",
                          windows: [WindowSnapshot(appName: "A", bundleIdentifier: "b",
                                                   rect: CGRect(x: 0, y: 0, width: 0.5, height: 1), screen: 1)],
                          screens: 2)
        let data = try JSONEncoder().encode([stack])
        let decoded = try decodeStacks(String(data: data, encoding: .utf8)!)
        #expect(decoded[0].id == stack.id)
        #expect(decoded[0].name == stack.name)
        #expect(decoded[0].screens == stack.screens)
        #expect(decoded[0].windows[0].id == stack.windows[0].id)
        #expect(decoded[0].windows[0].screen == stack.windows[0].screen)
        #expect(isClose(decoded[0].windows[0].rect, stack.windows[0].rect))
    }

    @Test("a window without an app name is rejected")
    func missingAppName() {
        let json = """
        [{"name":"X","windows":[{"bundleIdentifier":"b","rect":[[0,0],[1,1]]}]}]
        """
        #expect(throws: (any Error).self) { try decodeStacks(json) }
    }

    @Test("a window without any geometry is rejected")
    func missingGeometry() {
        let json = """
        [{"name":"X","windows":[{"appName":"A","bundleIdentifier":"b"}]}]
        """
        #expect(throws: (any Error).self) { try decodeStacks(json) }
    }
}
