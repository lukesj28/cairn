import SwiftUI
import CairnKit

struct StacksView: View {
    @ObservedObject var stackManager: StackManager
    let openSettings: () -> Void
    @State private var hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
    @State private var selectedStackID: Stack.ID?

    var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 210)
                .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 840, minHeight: 540)
        .background(
            Button("", action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .onAppear {
            hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
            ensureSelection()
        }
        .onChange(of: stackManager.stacks.map(\.id)) { _ in
            ensureSelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
        }
    }

    private func ensureSelection() {
        if let id = selectedStackID, stackManager.stacks.contains(where: { $0.id == id }) {
            return
        }
        selectedStackID = stackManager.stacks.first?.id
    }

    private var sidebarView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Stacks")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Text("\(stackManager.stacks.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if stackManager.stacks.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("No Stacks Saved")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Button {
                        addBlankStack()
                    } label: {
                        Label("New Stack", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedStackID) {
                    ForEach(stackManager.stacks) { stack in
                        StackRow(stack: stack, isSelected: stack.id == selectedStackID)
                            .tag(stack.id)
                            .contextMenu {
                                Button {
                                    let owning = ScreenGeometry.owningScreen()
                                    WindowEngine.open(stack: stack, owningScreen: owning)
                                } label: {
                                    Label("Apply Layout", systemImage: "play.fill")
                                }

                                Button {
                                    duplicateStack(stack)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    deleteStack(stack)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete(perform: stackManager.deleteStack)
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    addBlankStack()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .help("New Empty Stack")

                Button {
                    if let id = selectedStackID, let stack = stackManager.stacks.first(where: { $0.id == id }) {
                        deleteStack(stack)
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .disabled(selectedStackID == nil)
                .help("Delete Selected Stack")

                Spacer()

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var detailView: some View {
        VStack(spacing: 0) {
            if !hasPermissions {
                accessibilityBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let id = selectedStackID, stackManager.stacks.contains(where: { $0.id == id }) {
                StackEditorView(stackID: id, manager: stackManager)
            } else {
                emptyDetailState
            }
        }
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Permission Required")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                Text("Cairn requires accessibility access to move and tile windows across your displays.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Grant Access…") {
                _ = WindowEngine.isTrusted(promptIfNeeded: true)
                hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Grant Cairn permission in System Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.orange.opacity(0.25)),
            alignment: .bottom
        )
    }

    private var emptyDetailState: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 80, height: 80)
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 38))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 6) {
                Text("Select a Stack")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)

                Text("Choose a stack from the sidebar to inspect and arrange its layout, or create a new workspace.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            HStack(spacing: 12) {
                Button {
                    addBlankStack()
                } label: {
                    Label("New Blank Stack", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    snapshotToNewStack()
                } label: {
                    Label("Snapshot Current Windows", systemImage: "camera")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func addBlankStack() {
        createStack(windows: [])
    }

    private func snapshotToNewStack() {
        WindowEngine.snapshot(screens: 1) { windows in
            createStack(windows: windows)
        }
    }

    private func createStack(windows: [WindowSnapshot]) {
        let name = stackManager.nextDefaultStackName()
        let stack = Stack(name: name, windows: windows)
        stackManager.addStack(stack)
        selectedStackID = stack.id
    }

    private func duplicateStack(_ stack: Stack) {
        let duplicate = Stack(name: "\(stack.name) Copy", windows: stack.windows, screens: stack.screens)
        stackManager.addStack(duplicate)
        selectedStackID = duplicate.id
    }

    private func deleteStack(_ stack: Stack) {
        if selectedStackID == stack.id {
            selectedStackID = nil
        }
        stackManager.deleteStack(stack)
        ensureSelection()
    }
}

private struct StackRow: View {
    let stack: Stack
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: stack.screens > 1 ? "display.2" : "macwindow.on.rectangle")
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(stack.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)

                Text(summary)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private var summary: String {
        let win = "\(stack.windows.count) \(stack.windows.count == 1 ? "window" : "windows")"
        let scr = stack.screens == 1 ? "1 display" : "2 displays"
        return "\(win) · \(scr)"
    }
}
