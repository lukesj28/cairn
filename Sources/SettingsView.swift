import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var stackManager: StackManager
    @State private var hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)

    var body: some View {
        VStack(spacing: 0) {
            if !hasPermissions {
                VStack {
                    Text("Accessibility Permissions Required")
                        .font(.headline)
                    Text("Cairn needs permission to manipulate windows.")
                    Button("Request Permission") {
                        _ = WindowEngine.isTrusted(promptIfNeeded: true)
                        hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .padding()
            }

            NavigationView {
                List {
                    ForEach(stackManager.stacks) { stack in
                        NavigationLink(destination: StackDetailView(stack: stack, manager: stackManager)) {
                            Text(stack.name)
                        }
                    }
                    .onDelete(perform: stackManager.deleteStack)
                }
                .navigationTitle("Stacks")
                .toolbar {
                    ToolbarItem {
                        Button("New Stack") {
                            stackManager.addStack(Stack(name: "New Stack", windows: []))
                        }
                    }
                    ToolbarItem {
                        Button("Snapshot Current Layout") {
                            stackManager.addStack(Stack(name: "Snapshot \(Date().formatted(date: .abbreviated, time: .shortened))",
                                                        windows: WindowEngine.snapshot()))
                        }
                    }
                }

                Text("Select a stack to view details.")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
        }
    }
}

private enum EditorSpace {
    static let name = "cairn.editor"
}

struct CanvasFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct StackDetailView: View {
    @State var stack: Stack
    @ObservedObject var manager: StackManager
    @State private var selection: UUID?
    @State private var canvases: [Int: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Stack Name", text: $stack.name)
                .font(.title)
                .onChange(of: stack.name) { _ in
                    manager.updateStack(stack)
                }

            VStack(spacing: 8) {
                ForEach(Array(0..<stack.screens), id: \.self) { index in
                    ScreenCanvas(index: index, windows: $stack.windows, selection: $selection, onDrop: place)
                }
            }
            .coordinateSpace(name: EditorSpace.name)
            .onPreferenceChange(CanvasFrames.self) { canvases = $0 }

            HStack {
                Button("Add App…") { addApps() }
                Button("Remove Window") {
                    stack.windows.removeAll { $0.id == selection }
                    selection = nil
                    manager.updateStack(stack)
                }
                .disabled(selection == nil)
                Button("Snapshot Current Layout") {
                    stack.windows = WindowEngine.snapshot(screens: stack.screens)
                    selection = nil
                    manager.updateStack(stack)
                }
                if stack.screens < 2 {
                    Button("Add Monitor") {
                        stack.screens = 2
                        manager.updateStack(stack)
                    }
                } else {
                    Button("Remove Monitor") {
                        stack.windows.removeAll { $0.screen > 0 }
                        stack.screens = 1
                        selection = nil
                        manager.updateStack(stack)
                    }
                }
                Spacer()
                Button("Delete Stack") {
                    manager.deleteStack(stack)
                }
                .foregroundColor(.red)
            }

            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var caption: String {
        if stack.windows.isEmpty {
            return "Empty — add an app to place its window"
        }
        let base = "\(stack.windows.count) windows — drag to move, drag the corner to resize"
        return stack.screens < 2 ? base : base + ", drag onto the other screen to move it there"
    }

    private func place(id: UUID, box: CGRect, from index: Int) {
        guard let i = stack.windows.firstIndex(where: { $0.id == id }),
              let drop = ScreenGeometry.drop(box, from: index, canvases: canvases) else { return }
        stack.windows[i].screen = drop.screen
        stack.windows[i].rect = drop.rect
        selection = id
        manager.updateStack(stack)
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            let step = 0.03 * CGFloat(stack.windows.count % 6)
            stack.windows.append(WindowSnapshot(
                appName: url.deletingPathExtension().lastPathComponent,
                bundleIdentifier: bundleID,
                rect: ScreenGeometry.clamp(CGRect(x: 0.25 + step, y: 0.25 + step, width: 0.5, height: 0.5))))
        }
        selection = stack.windows.last?.id
        manager.updateStack(stack)
    }
}

struct ScreenCanvas: View {
    let index: Int
    @Binding var windows: [WindowSnapshot]
    @Binding var selection: UUID?
    var onDrop: (UUID, CGRect, Int) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .underPageBackgroundColor).opacity(index == 0 ? 1 : 0.55))
                ForEach(windows.indices.filter { windows[$0].screen == index }, id: \.self) { i in
                    WindowTile(window: windows[i],
                               canvas: geo.size,
                               isSelected: windows[i].id == selection,
                               onSelect: { selection = windows[i].id },
                               onDrop: { box in onDrop(windows[i].id, box, index) })
                }
                if index == 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.45))
                        .frame(height: 5)
                        .allowsHitTesting(false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(index == 0 ? 0.5 : 0.25),
                        style: StrokeStyle(lineWidth: 1, dash: index == 0 ? [] : [4, 3])))
            .preference(key: CanvasFrames.self, value: [index: geo.frame(in: .named(EditorSpace.name))])
        }
        .aspectRatio(ScreenGeometry.aspectRatio(ofScreen: index), contentMode: .fit)
        .frame(minHeight: 140)
    }
}

struct WindowTile: View {
    let window: WindowSnapshot
    let canvas: CGSize
    let isSelected: Bool
    var onSelect: () -> Void
    var onDrop: (CGRect) -> Void

    @State private var moveDelta: CGSize = .zero
    @State private var sizeDelta: CGSize = .zero

    private var pixels: CGRect {
        CGRect(x: window.rect.minX * canvas.width + moveDelta.width,
               y: window.rect.minY * canvas.height + moveDelta.height,
               width: max(24, window.rect.width * canvas.width + sizeDelta.width),
               height: max(18, window.rect.height * canvas.height + sizeDelta.height))
    }

    var body: some View {
        let box = pixels
        return ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 2) {
                if let icon = AppIcon.image(for: window.bundleIdentifier) {
                    Image(nsImage: icon).resizable().frame(width: 24, height: 24)
                }
                Text(window.appName).font(.caption2).lineLimit(1)
            }
            .frame(width: box.width, height: box.height)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(isSelected ? 0.35 : 0.18)))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(isSelected ? Color.accentColor : Color.secondary, lineWidth: isSelected ? 2 : 1))

            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 10, height: 10)
                .gesture(DragGesture()
                    .onChanged { g in onSelect(); sizeDelta = CGSize(width: g.translation.width, height: g.translation.height) }
                    .onEnded { _ in commit() })
        }
        .frame(width: box.width, height: box.height, alignment: .bottomTrailing)
        .offset(x: box.minX, y: box.minY)
        .onTapGesture { onSelect() }
        .gesture(DragGesture()
            .onChanged { g in onSelect(); moveDelta = g.translation }
            .onEnded { _ in commit() })
    }

    private func commit() {
        let box = pixels
        moveDelta = .zero
        sizeDelta = .zero
        onDrop(box)
    }
}

enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}
