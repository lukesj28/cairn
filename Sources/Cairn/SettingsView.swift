import SwiftUI
import Sparkle
import CairnKit

final class Navigation: ObservableObject {
    @Published var showingSettings = false
}

struct MainView: View {
    let stackManager: StackManager
    let updater: SPUUpdater
    @ObservedObject var navigation: Navigation

    var body: some View {
        if navigation.showingSettings {
            SettingsView(updater: updater, close: { navigation.showingSettings = false })
        } else {
            StacksView(stackManager: stackManager, openSettings: { navigation.showingSettings = true })
        }
    }
}

struct SettingsView: View {
    let updater: SPUUpdater
    let close: () -> Void
    @State private var automaticUpdates: Bool

    init(updater: SPUUpdater, close: @escaping () -> Void) {
        self.updater = updater
        self.close = close
        _automaticUpdates = State(initialValue: updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: close) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Settings")
                        .font(.title.weight(.semibold))

                    section("Updates") {
                        Toggle("Automatically install updates", isOn: $automaticUpdates)
                            .onChange(of: automaticUpdates) { enabled in
                                updater.automaticallyChecksForUpdates = enabled
                                updater.automaticallyDownloadsUpdates = enabled
                            }
                        Text("Cairn checks in the background and installs new versions silently. You can always use Check for Updates in the menu bar.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    section("Support") {
                        Text("Cairn is free and open source. If it saves you time, consider supporting its development.")
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            NSWorkspace.shared.open(kofiURL)
                        } label: {
                            Label {
                                Text("Support Cairn")
                            } icon: {
                                Image("KofiIcon", bundle: .module)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                }
                .frame(width: 460, alignment: .leading)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 840, minHeight: 540)
    }

    private let kofiURL = URL(string: "https://ko-fi.com/lukesj28")!

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(shape.stroke(Color(nsColor: .separatorColor)))
        }
    }
}
