import SwiftUI

struct SettingsView: View {
    @ObservedObject var profileManager: ProfileManager
    @State private var hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)

    var body: some View {
        VStack(spacing: 0) {
            if !hasPermissions {
                VStack {
                    Text("Accessibility Permissions Required")
                        .font(.headline)
                    Text("LayoutManager needs permission to manipulate windows.")
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
                    ForEach(profileManager.profiles) { profile in
                        NavigationLink(destination: ProfileDetailView(profile: profile, manager: profileManager)) {
                            Text(profile.name)
                        }
                    }
                    .onDelete(perform: profileManager.deleteProfile)
                }
                .navigationTitle("Profiles")
                .toolbar {
                    ToolbarItem {
                        Button("Snapshot Current Layout") {
                            let windows = WindowEngine.snapshot()
                            let newProfile = Profile(name: "New Profile", windows: windows, terminalCommands: [], browserURLs: [])
                            profileManager.addProfile(newProfile)
                        }
                    }
                }

                Text("Select a profile to view details.")
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            hasPermissions = WindowEngine.isTrusted(promptIfNeeded: false)
        }
    }
}

struct ProfileDetailView: View {
    @State var profile: Profile
    @ObservedObject var manager: ProfileManager

    var body: some View {
        Form {
            Section(header: Text("Profile Info")) {
                TextField("Profile Name", text: $profile.name)
                    .onChange(of: profile.name) { _ in
                        manager.updateProfile(profile)
                    }
                    .font(.title)
            }
            
            Section(header: Text("Windows Saved")) {
                if profile.windows.isEmpty {
                    Text("No windows in this profile")
                        .foregroundColor(.secondary)
                } else {
                    List(profile.windows) { window in
                        VStack(alignment: .leading) {
                            Text(window.appName).font(.headline)
                            Text(window.bundleIdentifier).font(.caption).foregroundColor(.secondary)
                            Text("X: \(Int(window.frame.origin.x)), Y: \(Int(window.frame.origin.y)), W: \(Int(window.frame.size.width)), H: \(Int(window.frame.size.height))").font(.caption2)
                        }
                    }
                }
            }
            
            Section(header: Text("Terminal Commands")) {
                if profile.terminalCommands.isEmpty {
                    Text("No terminal commands")
                        .foregroundColor(.secondary)
                } else {
                    List(profile.terminalCommands) { cmd in
                        VStack(alignment: .leading) {
                            Text(cmd.target.rawValue).font(.headline)
                            Text(cmd.command).font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            
            Section(header: Text("Browser URLs")) {
                if profile.browserURLs.isEmpty {
                    Text("No URLs")
                        .foregroundColor(.secondary)
                } else {
                    List(profile.browserURLs, id: \.self) { urlString in
                        Text(urlString).font(.system(.caption, design: .monospaced))
                    }
                }
            }

            Section {
                Button("Delete Profile") {
                    manager.deleteProfile(profile)
                }
                .foregroundColor(.red)
            }
        }
        .padding()
    }
}
