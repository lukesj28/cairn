import Foundation
import Combine

class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    private let fileManager = FileManager.default
    private let profilesURL: URL

    init() {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = paths[0].appendingPathComponent("WindowProfileManager")
        self.profilesURL = appSupportURL.appendingPathComponent("profiles.json")

        try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        loadProfiles()
    }

    func loadProfiles() {
        guard let data = try? Data(contentsOf: profilesURL) else { return }
        let decoder = JSONDecoder()
        if let loaded = try? decoder.decode([Profile].self, from: data) {
            DispatchQueue.main.async {
                self.profiles = loaded
            }
        }
    }

    func saveProfiles() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(profiles) {
            try? data.write(to: profilesURL)
        }
    }

    func addProfile(_ profile: Profile) {
        profiles.append(profile)
        saveProfiles()
    }

    func updateProfile(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
        }
    }

    func deleteProfile(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
    }

    func deleteProfile(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        saveProfiles()
    }
}
