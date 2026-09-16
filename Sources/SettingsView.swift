import SwiftUI

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
                        Button("Snapshot Current Layout") {
                            let windows = WindowEngine.snapshot()
                            let newStack = Stack(name: "New Stack", windows: windows, terminalCommands: [], browserURLs: [])
                            stackManager.addStack(newStack)
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

struct StackDetailView: View {
    @State var stack: Stack
    @ObservedObject var manager: StackManager

    var body: some View {
        Form {
            Section(header: Text("Stack Info")) {
                TextField("Stack Name", text: $stack.name)
                    .onChange(of: stack.name) { _ in
                        manager.updateStack(stack)
                    }
                    .font(.title)
            }
            
            Section(header: Text("Windows Saved")) {
                if stack.windows.isEmpty {
                    Text("No windows in this stack")
                        .foregroundColor(.secondary)
                } else {
                    List(stack.windows) { window in
                        VStack(alignment: .leading) {
                            Text(window.appName).font(.headline)
                            Text(window.bundleIdentifier).font(.caption).foregroundColor(.secondary)
                            Text("X: \(Int(window.frame.origin.x)), Y: \(Int(window.frame.origin.y)), W: \(Int(window.frame.size.width)), H: \(Int(window.frame.size.height))").font(.caption2)
                        }
                    }
                }
            }
            
            Section(header: Text("Terminal Commands")) {
                if stack.terminalCommands.isEmpty {
                    Text("No terminal commands")
                        .foregroundColor(.secondary)
                } else {
                    List(stack.terminalCommands) { cmd in
                        VStack(alignment: .leading) {
                            Text(cmd.target.rawValue).font(.headline)
                            Text(cmd.command).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            
            Section(header: Text("Browser URLs")) {
                if stack.browserURLs.isEmpty {
                    Text("No URLs")
                        .foregroundColor(.secondary)
                } else {
                    List(stack.browserURLs, id: \.self) { urlString in
                        Text(urlString).font(.system(.caption, design: .monospaced))
                    }
                }
            }

            Section {
                Button("Delete Stack") {
                    manager.deleteStack(stack)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }
}
