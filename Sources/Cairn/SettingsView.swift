import SwiftUI
import CairnKit

struct SettingsView: View {
    @ObservedObject var stackManager: StackManager
    @State private var hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
    @State private var selectedStackID: Stack.ID?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Text("Stacks").font(.headline)
                    Spacer()
                    Button {
                        stackManager.addStack(Stack(name: "New Stack", windows: []))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("New Stack")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                List(selection: $selectedStackID) {
                    ForEach(stackManager.stacks) { stack in
                        Text(stack.name).tag(stack.id)
                    }
                    .onDelete(perform: stackManager.deleteStack)
                }
                .listStyle(.sidebar)
            }

            if let id = selectedStackID {
                StackEditorView(stackID: id, manager: stackManager)
            } else {
                Text("Select a stack to view details.")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !hasPermissions {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Cairn needs Accessibility permission to move windows.")
                        .font(.caption)
                    Spacer()
                    Button("Allow") {
                        _ = WindowEngine.isTrusted(promptIfNeeded: true)
                        hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
                    }
                    .font(.caption)
                    .help("Grant Cairn permission to move windows")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(.thinMaterial)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
        }
    }
}
