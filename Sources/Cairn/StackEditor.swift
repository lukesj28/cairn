import SwiftUI
import UniformTypeIdentifiers
import CairnKit

struct StackEditorView: View {
    let stackID: UUID
    @ObservedObject var manager: StackManager

    @State private var selection: UUID?
    @State private var draftName = ""
    @State private var aspects: [CGFloat] = []
    @State private var isSnapshotting = false
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    private var stack: Stack? { manager.stacks.first { $0.id == stackID } }

    private func mutate(_ change: (inout Stack) -> Void) {
        guard var s = stack else { return }
        change(&s)
        manager.updateStack(s)
    }

    var body: some View {
        Group {
            if let stack {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Stack Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.title)
                        .focused($nameFocused)
                        .onSubmit { commitName() }
                        .onChange(of: nameFocused) { focused in if !focused { commitName() } }

                    actionBar(stack)

                    HStack(alignment: .top, spacing: 12) {
                        CanvasColumn(aspects: aspects,
                                    windows: stack.windows,
                                    selection: $selection,
                                    onCommit: place)

                        if let selectedWindow = stack.windows.first(where: { $0.id == selection }) {
                            TileInspector(window: selectedWindow,
                                         screens: stack.screens,
                                         onChange: updateWindow,
                                         onRemove: removeSelected)
                                .frame(width: 220)
                        }
                    }

                    Text("Drag to move, drag the corner to resize. Hold Shift for free placement.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                Text("This stack was deleted.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            draftName = stack?.name ?? ""
            refreshAspects()
        }
        .onChange(of: stackID) { _ in draftName = stack?.name ?? "" }
        .onChange(of: stack?.screens ?? 1) { _ in refreshAspects() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshAspects()
        }
        .confirmationDialog("Delete this stack?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let s = stack { manager.deleteStack(s) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func actionBar(_ stack: Stack) -> some View {
        HStack {
            Button { addApps() } label: { Image(systemName: "plus.app") }
                .help("Add App…")
            Button { snapshotLayout(stack) } label: { Image(systemName: "camera") }
                .help("Snapshot Layout")
                .disabled(isSnapshotting)
            if stack.screens < 2 {
                Button { mutate { $0.screens = 2 } } label: { Image(systemName: "plus.rectangle.on.rectangle") }
                    .help("Add Monitor")
            } else {
                Button {
                    selection = nil
                    mutate { s in
                        s.windows.removeAll { $0.screen > 0 }
                        s.screens = 1
                    }
                } label: { Image(systemName: "minus.rectangle") }
                    .help("Remove Monitor")
            }
            Spacer()
            Button { confirmingDelete = true } label: { Image(systemName: "trash") }
                .help("Delete Stack")
                .foregroundColor(.red)
        }
    }

    private func commitName() {
        guard let s = stack, s.name != draftName else { return }
        mutate { $0.name = draftName }
    }

    private func refreshAspects() {
        aspects = (0..<max(1, stack?.screens ?? 1)).map { ScreenGeometry.aspectRatio(ofScreen: $0) }
    }

    private func snapshotLayout(_ stack: Stack) {
        isSnapshotting = true
        WindowEngine.snapshot(screens: stack.screens) { windows in
            isSnapshotting = false
            selection = nil
            mutate { $0.windows = windows }
        }
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            appendApps(panel.urls)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private func appendApps(_ urls: [URL]) {
        guard var windows = stack?.windows else { return }
        for url in urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            let step = 0.03 * CGFloat(windows.count % 6)
            windows.append(WindowSnapshot(
                appName: url.deletingPathExtension().lastPathComponent,
                bundleIdentifier: bundleID,
                rect: ScreenGeometry.clamp(CGRect(x: 0.25 + step, y: 0.25 + step, width: 0.5, height: 0.5))))
        }
        selection = windows.last?.id
        mutate { $0.windows = windows }
    }

    private func updateWindow(_ updated: WindowSnapshot) {
        mutate { s in
            guard let i = s.windows.firstIndex(where: { $0.id == updated.id }) else { return }
            s.windows[i] = updated
        }
    }

    private func removeSelected() {
        guard let id = selection else { return }
        selection = nil
        mutate { s in s.windows.removeAll { $0.id == id } }
    }

    private func place(id: UUID, rect: CGRect, screen: Int, free: Bool, isResize: Bool) {
        guard let stack else { return }
        let siblings = stack.windows.filter { $0.screen == screen && $0.id != id }.map(\.rect)
        let result: CGRect
        if free {
            result = ScreenGeometry.clamp(rect)
        } else if isResize {
            result = SnapGrid.snapResize(rect, neighbours: siblings)
        } else {
            result = SnapGrid.snapMove(rect, neighbours: siblings)
        }
        selection = id
        mutate { s in
            guard let i = s.windows.firstIndex(where: { $0.id == id }) else { return }
            s.windows[i].screen = screen
            s.windows[i].rect = result
        }
    }
}

private struct CanvasColumn: View {
    let aspects: [CGFloat]
    let windows: [WindowSnapshot]
    @Binding var selection: UUID?
    var onCommit: (UUID, CGRect, Int, Bool, Bool) -> Void

    var body: some View {
        GeometryReader { geo in
            let rects = CanvasLayout.rects(in: geo.size, aspects: aspects, spacing: 8)
            let canvases = Dictionary(uniqueKeysWithValues: rects.enumerated().map { ($0.offset, $0.element) })
            ZStack(alignment: .topLeading) {
                ForEach(rects.indices, id: \.self) { i in
                    ScreenCanvas(index: i,
                                size: rects[i].size,
                                windows: windows.filter { $0.screen == i },
                                selection: $selection,
                                onCommit: { id, box, free, isResize in
                                    if isResize {
                                        guard let canvas = canvases[i], canvas.width > 0, canvas.height > 0 else { return }
                                        let fraction = CGRect(x: box.minX / canvas.width, y: box.minY / canvas.height,
                                                              width: box.width / canvas.width, height: box.height / canvas.height)
                                        onCommit(id, fraction, i, free, true)
                                    } else if let drop = ScreenGeometry.drop(box, from: i, canvases: canvases) {
                                        onCommit(id, drop.rect, drop.screen, free, false)
                                    }
                                })
                        .frame(width: rects[i].width, height: rects[i].height)
                        .offset(x: rects[i].minX, y: rects[i].minY)
                }
            }
        }
    }
}

private struct ScreenCanvas: View {
    let index: Int
    let size: CGSize
    let windows: [WindowSnapshot]
    @Binding var selection: UUID?
    var onCommit: (UUID, CGRect, Bool, Bool) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .underPageBackgroundColor).opacity(index == 0 ? 1 : 0.55))
            GridLines(columns: SnapGrid.columns, rows: SnapGrid.rows)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
                .allowsHitTesting(false)
            ForEach(windows) { window in
                WindowTile(window: window,
                          canvas: size,
                          neighbours: windows.filter { $0.id != window.id }.map(\.rect),
                          isSelected: window.id == selection,
                          onSelect: { selection = window.id },
                          onCommit: { box, free, isResize in onCommit(window.id, box, free, isResize) })
                    .zIndex(window.id == selection ? 1 : 0)
            }
            if index == 0 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(height: 5)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(index == 0 ? 0.5 : 0.25),
                    style: StrokeStyle(lineWidth: 1, dash: index == 0 ? [] : [4, 3])))
    }
}

private struct GridLines: Shape {
    let columns: Int
    let rows: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for c in 1..<max(1, columns) {
            let x = rect.minX + rect.width * CGFloat(c) / CGFloat(columns)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for r in 1..<max(1, rows) {
            let y = rect.minY + rect.height * CGFloat(r) / CGFloat(rows)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct WindowTile: View {
    let window: WindowSnapshot
    let canvas: CGSize
    let neighbours: [CGRect]
    let isSelected: Bool
    var onSelect: () -> Void
    var onCommit: (CGRect, Bool, Bool) -> Void

    @State private var start: CGRect?
    @State private var live: CGRect?

    private var isFree: Bool { NSEvent.modifierFlags.contains(.shift) }

    private var pixels: CGRect {
        let fraction = live ?? window.rect
        return CGRect(x: fraction.minX * canvas.width, y: fraction.minY * canvas.height,
                      width: fraction.width * canvas.width, height: fraction.height * canvas.height)
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
                    .onChanged(handleResize)
                    .onEnded { _ in endResize() })
        }
        .frame(width: box.width, height: box.height, alignment: .bottomTrailing)
        .offset(x: box.minX, y: box.minY)
        .onTapGesture { onSelect() }
        .gesture(DragGesture()
            .onChanged(handleMove)
            .onEnded { _ in endMove() })
    }

    private func handleMove(_ g: DragGesture.Value) {
        if start == nil {
            start = window.rect
            onSelect()
        }
        guard let start else { return }
        let proposed = CGRect(x: start.minX + g.translation.width / canvas.width,
                              y: start.minY + g.translation.height / canvas.height,
                              width: start.width, height: start.height)
        if !(0...1).contains(proposed.midX) || !(0...1).contains(proposed.midY) {
            live = proposed
        } else {
            live = isFree ? ScreenGeometry.clamp(proposed) : SnapGrid.snapMove(proposed, neighbours: neighbours)
        }
    }

    private func endMove() {
        onCommit(pixels, isFree, false)
        start = nil
        live = nil
    }

    private func handleResize(_ g: DragGesture.Value) {
        if start == nil {
            start = window.rect
            onSelect()
        }
        guard let start else { return }
        let proposed = CGRect(x: start.minX, y: start.minY,
                              width: max(0, start.width + g.translation.width / canvas.width),
                              height: max(0, start.height + g.translation.height / canvas.height))
        live = isFree ? ScreenGeometry.clamp(proposed) : SnapGrid.snapResize(proposed, neighbours: neighbours)
    }

    private func endResize() {
        onCommit(pixels, isFree, true)
        start = nil
        live = nil
    }
}

private struct TileInspector: View {
    let window: WindowSnapshot
    let screens: Int
    var onChange: (WindowSnapshot) -> Void
    var onRemove: () -> Void

    @State private var draft: [String] = ["", "", "", ""]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let icon = AppIcon.image(for: window.bundleIdentifier) {
                    Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                }
                Text(window.appName).font(.headline)
            }
            Text(window.bundleIdentifier)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if screens == 2 {
                Picker("Screen", selection: Binding(
                    get: { window.screen },
                    set: { newValue in
                        var updated = window
                        updated.screen = newValue
                        onChange(updated)
                    })) {
                    Text("1").tag(0)
                    Text("2").tag(1)
                }
                .pickerStyle(.segmented)
                .help("Move to the other screen")
            }

            VStack(alignment: .leading, spacing: 6) {
                percentRow("X", 0)
                percentRow("Y", 1)
                percentRow("W", 2)
                percentRow("H", 3)
            }

            Spacer()

            Button(role: .destructive) { onRemove() } label: { Image(systemName: "trash") }
                .help("Remove Window")
        }
        .padding()
        .onAppear { seed() }
        .onChange(of: window.id) { _ in seed() }
        .onChange(of: window.rect) { _ in seed() }
    }

    private func percentRow(_ label: String, _ index: Int) -> some View {
        HStack {
            Text(label)
                .frame(width: 14, alignment: .leading)
                .foregroundColor(.secondary)
            TextField("", text: $draft[index])
                .multilineTextAlignment(.trailing)
                .frame(width: 40)
                .onSubmit { commit() }
            Text("%")
                .foregroundColor(.secondary)
                .frame(width: 14, alignment: .leading)
        }
    }

    private func seed() {
        let values = [window.rect.minX, window.rect.minY, window.rect.width, window.rect.height]
        draft = values.map { String(Int(($0 * 100).rounded())) }
    }

    private func commit() {
        let current = [window.rect.minX, window.rect.minY, window.rect.width, window.rect.height]
        var values: [Double] = []
        var ok = true
        for i in 0..<4 {
            if let v = Double(draft[i]) {
                values.append(v)
            } else {
                draft[i] = String(Int((current[i] * 100).rounded()))
                values.append(current[i] * 100)
                ok = false
            }
        }
        guard ok else { return }
        var updated = window
        updated.rect = ScreenGeometry.clamp(CGRect(x: values[0] / 100, y: values[1] / 100,
                                                    width: values[2] / 100, height: values[3] / 100))
        onChange(updated)
    }
}
