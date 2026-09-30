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
    @State private var keyMonitor: Any?
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
                VStack(alignment: .leading, spacing: 12) {
                    headerBar(stack)

                    Divider()

                    HStack(alignment: .top, spacing: 14) {
                        CanvasColumn(aspects: aspects,
                                     windows: stack.windows,
                                     selection: $selection,
                                     onCommit: place,
                                     onRemove: removeWindow)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        inspectorPanel(stack)
                            .frame(width: 215)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    footerBar(stack)
                }
                .padding(16)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("This stack was deleted.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            draftName = stack?.name ?? ""
            refreshAspects()
            setupKeyboardMonitor()
        }
        .onDisappear {
            teardownKeyboardMonitor()
        }
        .onChange(of: stackID) { _ in
            draftName = stack?.name ?? ""
            selection = nil
        }
        .onChange(of: stack?.screens ?? 1) { _ in refreshAspects() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            refreshAspects()
        }
        .confirmationDialog("Delete this stack?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Stack", role: .destructive) {
                if let s = stack { manager.deleteStack(s) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(stack?.name ?? "this stack")\"? This action cannot be undone.")
        }
    }

    @ViewBuilder
    private func headerBar(_ stack: Stack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                TextField("Stack Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.bold))
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onChange(of: nameFocused) { focused in if !focused { commitName() } }

                Spacer(minLength: 12)

                Button {
                    let owning = ScreenGeometry.owningScreen()
                    WindowEngine.open(stack: stack, owningScreen: owning)
                } label: {
                    Label("Apply", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .fixedSize()
                .help("Tile all open windows according to this stack")

                Button {
                    confirmingDelete = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .fixedSize()
                .help("Delete Stack")
            }

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow")
                    Text("\(stack.windows.count) \(stack.windows.count == 1 ? "window" : "windows")")

                    Text("•")

                    Image(systemName: stack.screens == 1 ? "display" : "display.2")
                    Text(stack.screens == 1 ? "Single Display" : "Dual Displays")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize()

                Spacer(minLength: 12)

                Picker("", selection: Binding(
                    get: { stack.screens },
                    set: { newScreens in
                        if newScreens < stack.screens {
                            selection = nil
                            mutate { s in
                                s.windows.removeAll { $0.screen > 0 }
                                s.screens = 1
                            }
                        } else {
                            mutate { $0.screens = 2 }
                        }
                    }
                )) {
                    Label("1 Display", systemImage: "display").tag(1)
                    Label("2 Displays", systemImage: "display.2").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                .fixedSize()

                Button {
                    addApps()
                } label: {
                    Label("Add App…", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .help("Add an application window to this stack")

                Button {
                    snapshotLayout(stack)
                } label: {
                    HStack(spacing: 5) {
                        if isSnapshotting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Capturing…")
                        } else {
                            Image(systemName: "camera")
                            Text("Snapshot")
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSnapshotting)
                .fixedSize()
                .help("Capture current positions of open windows into this stack")
            }
        }
    }

    @ViewBuilder
    private func inspectorPanel(_ stack: Stack) -> some View {
        if let selectedWindow = stack.windows.first(where: { $0.id == selection }) {
            TileInspector(window: selectedWindow,
                          screens: stack.screens,
                          onChange: updateWindow,
                          onRemove: removeSelected)
        } else {
            StackOverviewInspector(stack: stack,
                                   onAddApp: addApps,
                                   onSnapshot: { snapshotLayout(stack) },
                                   isSnapshotting: isSnapshotting)
        }
    }

    private func footerBar(_ stack: Stack) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
                .font(.caption)

            Text("Drag to move · Drag any edge or corner to resize · Hold ⇧ for free placement · ⌫ to delete")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if selection != nil {
                Button("Deselect") {
                    selection = nil
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 4)
    }

    private func setupKeyboardMonitor() {
        teardownKeyboardMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 51 && !nameFocused {
                if selection != nil {
                    removeSelected()
                    return nil
                }
            } else if event.keyCode == 53 {
                if selection != nil {
                    selection = nil
                    return nil
                }
            }
            return event
        }
    }

    private func teardownKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func commitName() {
        guard let s = stack, !draftName.trimmingCharacters(in: .whitespaces).isEmpty, s.name != draftName else { return }
        mutate { $0.name = draftName.trimmingCharacters(in: .whitespaces) }
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

    private func removeWindow(id: UUID) {
        if selection == id {
            selection = nil
        }
        mutate { s in s.windows.removeAll { $0.id == id } }
    }

    private func place(id: UUID, rect: CGRect, screen: Int, free: Bool, isResize: Bool, original: CGRect?) {
        guard let stack else { return }
        let siblings = stack.windows.filter { $0.screen == screen && $0.id != id }.map(\.rect)
        let result: CGRect
        if free {
            result = ScreenGeometry.clamp(rect)
        } else if isResize {
            result = SnapGrid.snapResize(rect: rect, original: original ?? rect, neighbours: siblings)
        } else {
            result = SnapGrid.snapMove(rect, neighbours: siblings)
        }
        selection = id
        withAnimation(.easeOut(duration: 0.15)) {
            mutate { s in
                guard let i = s.windows.firstIndex(where: { $0.id == id }) else { return }
                s.windows[i].screen = screen
                s.windows[i].rect = result
            }
        }
    }
}

private struct CanvasColumn: View {
    let aspects: [CGFloat]
    let windows: [WindowSnapshot]
    @Binding var selection: UUID?
    var onCommit: (UUID, CGRect, Int, Bool, Bool, CGRect?) -> Void
    var onRemove: (UUID) -> Void

    var body: some View {
        GeometryReader { geo in
            let rects = CanvasLayout.rects(in: geo.size, aspects: aspects, spacing: 14)
            let totalHeight = rects.last.map(\.maxY) ?? 0
            let offsetY = max(0, (geo.size.height - totalHeight) / 2)
            let canvases = Dictionary(uniqueKeysWithValues: rects.enumerated().map { ($0.offset, $0.element) })

            ZStack(alignment: .topLeading) {
                ForEach(rects.indices, id: \.self) { i in
                    ScreenCanvas(index: i,
                                 size: rects[i].size,
                                 windows: windows.filter { $0.screen == i },
                                 selection: $selection,
                                 onCommit: { id, box, free, isResize, orig in
                                     if isResize {
                                         guard let canvas = canvases[i], canvas.width > 0, canvas.height > 0 else { return }
                                         let fraction = CGRect(x: box.minX / canvas.width, y: box.minY / canvas.height,
                                                               width: box.width / canvas.width, height: box.height / canvas.height)
                                         onCommit(id, fraction, i, free, true, orig)
                                     } else if let drop = ScreenGeometry.drop(box, from: i, canvases: canvases) {
                                         onCommit(id, drop.rect, drop.screen, free, false, orig)
                                     }
                                 },
                                 onRemove: onRemove)
                        .frame(width: rects[i].width, height: rects[i].height)
                        .offset(x: rects[i].minX, y: rects[i].minY + offsetY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

private struct ScreenCanvas: View {
    let index: Int
    let size: CGSize
    let windows: [WindowSnapshot]
    @Binding var selection: UUID?
    var onCommit: (UUID, CGRect, Bool, Bool, CGRect?) -> Void
    var onRemove: (UUID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor).opacity(0.85),
                            Color(nsColor: .controlBackgroundColor).opacity(0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            GridLines(columns: SnapGrid.columns, rows: SnapGrid.rows)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 0.5)
                .allowsHitTesting(false)

            CenterGuides()
                .stroke(Color.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 0.75, dash: [4, 4]))
                .allowsHitTesting(false)

            if windows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "plus.viewfinder")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(index == 0 ? "No Windows on Main Display" : "No Windows on Display 2")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("Click Add App above to place windows")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            ForEach(windows) { window in
                WindowTile(window: window,
                           canvasIndex: index,
                           canvas: size,
                           neighbours: windows.filter { $0.id != window.id }.map(\.rect),
                           isSelected: window.id == selection,
                           onSelect: { selection = window.id },
                           onCommit: { box, free, isResize, orig in onCommit(window.id, box, free, isResize, orig) },
                           onRemove: { onRemove(window.id) })
                    .zIndex(window.id == selection ? 2 : 1)
            }

            displayBadge
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "ScreenCanvas_\(index)")
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private var displayBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: index == 0 ? "display" : "display.2")
                .font(.system(size: 8))
            Text(index == 0 ? "Display 1 (Main)" : "Display 2")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
        )
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

private struct CenterGuides: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        path.move(to: CGPoint(x: midX, y: rect.minY))
        path.addLine(to: CGPoint(x: midX, y: rect.maxY))

        let midY = rect.midY
        path.move(to: CGPoint(x: rect.minX, y: midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: midY))
        return path
    }
}

enum ResizeDirection: Equatable {
    case top, bottom, leading, trailing
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    var affectsLeading: Bool { self == .leading || self == .topLeading || self == .bottomLeading }
    var affectsTrailing: Bool { self == .trailing || self == .topTrailing || self == .bottomTrailing }
    var affectsTop: Bool { self == .top || self == .topLeading || self == .topTrailing }
    var affectsBottom: Bool { self == .bottom || self == .bottomLeading || self == .bottomTrailing }
}

private struct WindowTile: View {
    let window: WindowSnapshot
    let canvasIndex: Int
    let canvas: CGSize
    let neighbours: [CGRect]
    let isSelected: Bool
    var onSelect: () -> Void
    var onCommit: (CGRect, Bool, Bool, CGRect?) -> Void
    var onRemove: () -> Void

    @State private var start: CGRect?
    @State private var live: CGRect?
    @State private var isHovered = false

    private var coordinateSpaceName: String { "ScreenCanvas_\(canvasIndex)" }
    private var isFree: Bool { NSEvent.modifierFlags.contains(.shift) }

    private var pixels: CGRect {
        let fraction = live ?? window.rect
        return CGRect(x: fraction.minX * canvas.width, y: fraction.minY * canvas.height,
                      width: fraction.width * canvas.width, height: fraction.height * canvas.height)
    }

    var body: some View {
        let box = pixels
        return ZStack(alignment: .topLeading) {
            windowBody(box: box)
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpaceName))
                        .onChanged(handleMove)
                        .onEnded { _ in endMove() }
                )

            ResizeEdgeStrip(cursor: .resizeUpDown)
                .frame(width: max(0, box.width - 20), height: 6)
                .offset(x: 10, y: -3)
                .gesture(resizeGesture(for: .top))

            ResizeEdgeStrip(cursor: .resizeUpDown)
                .frame(width: max(0, box.width - 20), height: 6)
                .offset(x: 10, y: box.height - 3)
                .gesture(resizeGesture(for: .bottom))

            ResizeEdgeStrip(cursor: .resizeLeftRight)
                .frame(width: 6, height: max(0, box.height - 20))
                .offset(x: -3, y: 10)
                .gesture(resizeGesture(for: .leading))

            ResizeEdgeStrip(cursor: .resizeLeftRight)
                .frame(width: 6, height: max(0, box.height - 20))
                .offset(x: box.width - 3, y: 10)
                .gesture(resizeGesture(for: .trailing))

            ResizeCornerHandle(cursor: .crosshair)
                .frame(width: 14, height: 14)
                .offset(x: -4, y: -4)
                .gesture(resizeGesture(for: .topLeading))

            ResizeCornerHandle(cursor: .crosshair)
                .frame(width: 14, height: 14)
                .offset(x: box.width - 10, y: -4)
                .gesture(resizeGesture(for: .topTrailing))

            ResizeCornerHandle(cursor: .crosshair)
                .frame(width: 14, height: 14)
                .offset(x: -4, y: box.height - 10)
                .gesture(resizeGesture(for: .bottomLeading))

            ResizeCornerHandle(cursor: .crosshair, showGrip: true, isSelected: isSelected || isHovered)
                .frame(width: 16, height: 16)
                .offset(x: box.width - 12, y: box.height - 12)
                .gesture(resizeGesture(for: .bottomTrailing))
        }
        .frame(width: box.width, height: box.height, alignment: .topLeading)
        .offset(x: box.minX, y: box.minY)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if !isSelected { onSelect() }
        }
    }

    private func resizeGesture(for dir: ResizeDirection) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { g in
                handleResize(dir: dir, g: g)
            }
            .onEnded { _ in
                endResize()
            }
    }

    @ViewBuilder
    private func windowBody(box: CGRect) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                HStack(spacing: 2.5) {
                    Circle().fill(Color.red.opacity(0.85)).frame(width: 3.5, height: 3.5)
                    Circle().fill(Color.yellow.opacity(0.85)).frame(width: 3.5, height: 3.5)
                    Circle().fill(Color.green.opacity(0.85)).frame(width: 3.5, height: 3.5)
                }
                .padding(.leading, 3)

                if box.width >= 70 {
                    Text(window.appName)
                        .font(.system(size: 8.5, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundColor(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 0)
                }

                if isHovered || isSelected {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 3)
                    .help("Remove Window")
                } else {
                    Color.clear.frame(width: 8, height: 8)
                }
            }
            .frame(height: 14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            .overlay(
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5),
                alignment: .bottom
            )

            VStack(spacing: 2) {
                Spacer(minLength: 0)

                let iconDimension = min(26, max(14, min(box.width - 12, box.height - 24)))
                if let icon = AppIcon.image(for: window.bundleIdentifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconDimension, height: iconDimension)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: iconDimension * 0.7))
                        .foregroundColor(.secondary)
                }

                if box.width < 70 && box.height >= 40 {
                    Text(window.appName)
                        .font(.system(size: 7.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if box.height >= 48 && box.width >= 48 {
                    Text("\(Int((window.rect.width * 100).rounded()))% × \(Int((window.rect.height * 100).rounded()))%")
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(2)
        }
        .frame(width: box.width, height: box.height)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(isSelected ? 0.12 : (isHovered ? 0.05 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isSelected ? Color.accentColor : (isHovered ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.14)),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(
            color: Color.black.opacity(isSelected ? 0.22 : (isHovered ? 0.16 : 0.08)),
            radius: isSelected ? 6 : (isHovered ? 4 : 2),
            x: 0,
            y: isSelected ? 3 : 1
        )
    }

    private func handleMove(g: DragGesture.Value) {
        if start == nil {
            start = window.rect
            if !isSelected { onSelect() }
        }
        guard let start else { return }
        let proposedX = start.minX + g.translation.width / max(1, canvas.width)
        let proposedY = start.minY + g.translation.height / max(1, canvas.height)
        let proposed = CGRect(x: proposedX, y: proposedY, width: start.width, height: start.height)

        if !(0...1).contains(proposed.midX) || !(0...1).contains(proposed.midY) {
            live = proposed
        } else if isFree {
            live = ScreenGeometry.clamp(proposed)
        } else {
            let thresholdX: CGFloat = max(0.02, 12.0 / max(1, canvas.width))
            let thresholdY: CGFloat = max(0.02, 12.0 / max(1, canvas.height))
            var posX = proposed.minX
            var posY = proposed.minY

            let targetsX = [0.0, 1.0] + neighbours.map(\.minX) + neighbours.map(\.maxX)
            for target in targetsX {
                if abs(proposed.minX - target) <= thresholdX {
                    posX = target
                    break
                } else if abs(proposed.maxX - target) <= thresholdX {
                    posX = target - proposed.width
                    break
                }
            }

            let targetsY = [0.0, 1.0] + neighbours.map(\.minY) + neighbours.map(\.maxY)
            for target in targetsY {
                if abs(proposed.minY - target) <= thresholdY {
                    posY = target
                    break
                } else if abs(proposed.maxY - target) <= thresholdY {
                    posY = target - proposed.height
                    break
                }
            }

            live = ScreenGeometry.clamp(CGRect(x: posX, y: posY, width: proposed.width, height: proposed.height))
        }
    }

    private func endMove() {
        let finalPixels = pixels
        let initialRect = start
        start = nil
        live = nil
        onCommit(finalPixels, isFree, false, initialRect)
    }

    private func handleResize(dir: ResizeDirection, g: DragGesture.Value) {
        if start == nil {
            start = window.rect
            if !isSelected { onSelect() }
        }
        guard let start else { return }

        let dx = g.translation.width / max(1, canvas.width)
        let dy = g.translation.height / max(1, canvas.height)
        let minW = 1.0 / CGFloat(SnapGrid.columns)
        let minH = 1.0 / CGFloat(SnapGrid.rows)

        var proposedX = start.minX
        var proposedY = start.minY
        var proposedW = start.width
        var proposedH = start.height

        if dir.affectsLeading {
            let newLeft = min(start.maxX - minW, start.minX + dx)
            proposedX = newLeft
            proposedW = start.maxX - newLeft
        } else if dir.affectsTrailing {
            proposedW = max(minW, start.width + dx)
        }

        if dir.affectsTop {
            let newTop = min(start.maxY - minH, start.minY + dy)
            proposedY = newTop
            proposedH = start.maxY - newTop
        } else if dir.affectsBottom {
            proposedH = max(minH, start.height + dy)
        }

        if isFree {
            live = ScreenGeometry.clamp(CGRect(x: proposedX, y: proposedY, width: proposedW, height: proposedH))
        } else {
            let thresholdX: CGFloat = max(0.02, 12.0 / max(1, canvas.width))
            let thresholdY: CGFloat = max(0.02, 12.0 / max(1, canvas.height))
            let targetsX = [0.0, 1.0] + neighbours.map(\.minX) + neighbours.map(\.maxX)
            let targetsY = [0.0, 1.0] + neighbours.map(\.minY) + neighbours.map(\.maxY)

            if dir.affectsLeading {
                for target in targetsX {
                    if abs(proposedX - target) <= thresholdX {
                        let snappedX = min(start.maxX - minW, target)
                        proposedW = start.maxX - snappedX
                        proposedX = snappedX
                        break
                    }
                }
            } else if dir.affectsTrailing {
                for target in targetsX {
                    let rightEdge = proposedX + proposedW
                    if abs(rightEdge - target) <= thresholdX {
                        proposedW = max(minW, target - proposedX)
                        break
                    }
                }
            }

            if dir.affectsTop {
                for target in targetsY {
                    if abs(proposedY - target) <= thresholdY {
                        let snappedY = min(start.maxY - minH, target)
                        proposedH = start.maxY - snappedY
                        proposedY = snappedY
                        break
                    }
                }
            } else if dir.affectsBottom {
                for target in targetsY {
                    let bottomEdge = proposedY + proposedH
                    if abs(bottomEdge - target) <= thresholdY {
                        proposedH = max(minH, target - proposedY)
                        break
                    }
                }
            }

            live = ScreenGeometry.clamp(CGRect(x: proposedX, y: proposedY, width: proposedW, height: proposedH))
        }
    }

    private func endResize() {
        let finalPixels = pixels
        let initialRect = start
        start = nil
        live = nil
        onCommit(finalPixels, isFree, true, initialRect)
    }
}

private struct ResizeEdgeStrip: View {
    let cursor: NSCursor
    @State private var isHovering = false

    var body: some View {
        Color.white.opacity(0.001)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering && !isHovering {
                    isHovering = true
                    cursor.push()
                } else if !hovering && isHovering {
                    isHovering = false
                    NSCursor.pop()
                }
            }
            .onDisappear {
                if isHovering {
                    isHovering = false
                    NSCursor.pop()
                }
            }
    }
}

private struct ResizeCornerHandle: View {
    let cursor: NSCursor
    var showGrip: Bool = false
    var isSelected: Bool = false
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.white.opacity(0.001)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showGrip {
                Path { path in
                    path.move(to: CGPoint(x: 12, y: 4))
                    path.addLine(to: CGPoint(x: 4, y: 12))

                    path.move(to: CGPoint(x: 12, y: 8))
                    path.addLine(to: CGPoint(x: 8, y: 12))
                }
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.65), lineWidth: 1.5)
                .frame(width: 12, height: 12)
                .padding(2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering && !isHovering {
                isHovering = true
                cursor.push()
            } else if !hovering && isHovering {
                isHovering = false
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovering {
                isHovering = false
                NSCursor.pop()
            }
        }
    }
}

private struct TileInspector: View {
    let window: WindowSnapshot
    let screens: Int
    var onChange: (WindowSnapshot) -> Void
    var onRemove: () -> Void

    @State private var draft: [String] = ["", "", "", ""]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let icon = AppIcon.image(for: window.bundleIdentifier) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                } else {
                    Image(systemName: "macwindow")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(window.appName)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Text(window.bundleIdentifier)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Divider()

            if screens == 2 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DISPLAY")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.secondary)

                    Picker("Display", selection: Binding(
                        get: { window.screen },
                        set: { newValue in
                            var updated = window
                            updated.screen = newValue
                            onChange(updated)
                        })) {
                        Text("Display 1").tag(0)
                        Text("Display 2").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                Divider()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("QUICK PRESETS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    presetButton(title: "Left 1/2", icon: "rectangle.lefthalf.filled",
                                 rect: CGRect(x: 0, y: 0, width: 0.5, height: 1.0))
                    presetButton(title: "Right 1/2", icon: "rectangle.righthalf.filled",
                                 rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1.0))
                    presetButton(title: "Top 1/2", icon: "rectangle.tophalf.filled",
                                 rect: CGRect(x: 0, y: 0, width: 1.0, height: 0.5))
                    presetButton(title: "Bottom 1/2", icon: "rectangle.bottomhalf.filled",
                                 rect: CGRect(x: 0, y: 0.5, width: 1.0, height: 0.5))
                    presetButton(title: "Full", icon: "rectangle.fill",
                                 rect: CGRect(x: 0, y: 0, width: 1.0, height: 1.0))
                    presetButton(title: "Center", icon: "rectangle.inset.filled",
                                 rect: CGRect(x: 0.15, y: 0.1, width: 0.7, height: 0.8))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("GEOMETRY")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)

                percentRow("X", 0)
                percentRow("Y", 1)
                percentRow("W", 2)
                percentRow("H", 3)
            }

            Spacer(minLength: 4)

            Divider()

            Button(role: .destructive) {
                onRemove()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Remove Window")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Remove this window from the stack")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        )
        .onAppear { seed() }
        .onChange(of: window.id) { _ in seed() }
        .onChange(of: window.rect) { _ in seed() }
    }

    private func presetButton(title: String, icon: String, rect: CGRect) -> some View {
        Button {
            var updated = window
            updated.rect = rect
            onChange(updated)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func percentRow(_ label: String, _ index: Int) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 14, alignment: .leading)
                .foregroundColor(.secondary)

            Button {
                step(index, delta: -5)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 8.5))
            }
            .buttonStyle(.borderless)
            .frame(width: 14, height: 14)

            TextField("", text: $draft[index])
                .font(.system(size: 11, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 34)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit() }

            Button {
                step(index, delta: 5)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 8.5))
            }
            .buttonStyle(.borderless)
            .frame(width: 14, height: 14)

            Text("%")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
        }
    }

    private func step(_ index: Int, delta: Double) {
        let current = Double(draft[index]) ?? 0
        let newValue = max(0, min(100, current + delta))
        draft[index] = String(Int(newValue.rounded()))
        commit()
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

private struct StackOverviewInspector: View {
    let stack: Stack
    var onAddApp: () -> Void
    var onSnapshot: () -> Void
    let isSnapshotting: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 15))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stack Overview")
                        .font(.system(size: 13, weight: .bold))
                    Text("\(stack.windows.count) \(stack.windows.count == 1 ? "window" : "windows") · \(stack.screens == 1 ? "1 display" : "2 displays")")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("WINDOW ARRANGEMENT")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)

                Text("Click any window tile on the canvas to inspect its geometry, choose quick presets (halves, full screen, thirds), or reassign displays.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }

            Divider()

            VStack(spacing: 8) {
                Button {
                    onAddApp()
                } label: {
                    Label("Add Application…", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    onSnapshot()
                } label: {
                    HStack(spacing: 5) {
                        if isSnapshotting {
                            ProgressView().controlSize(.small)
                            Text("Capturing…")
                        } else {
                            Image(systemName: "camera")
                            Text("Snapshot Layout")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isSnapshotting)
            }

            Spacer(minLength: 4)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("TIPS & SHORTCUTS")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.secondary)
                Text("• Drag any edge or corner to resize\n• Magnetic snap aligns to edges\n• Hold ⇧ for free placement\n• ⌫ removes selected window\n• Esc deselects window")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        )
    }
}
