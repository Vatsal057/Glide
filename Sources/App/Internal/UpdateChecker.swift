import Foundation

/// Checks GitHub Releases for a newer version than the running app.
/// No Sparkle, no appcast — one API call, compare tags, link out to download.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    @Published private(set) var state: State = .idle

    private static let latestReleaseAPI =
        URL(string: "https://api.github.com/repos/Vatsal057/Glide/releases/latest")!

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func check() {
        guard state != .checking else { return }
        state = .checking
        Task {
            do {
                var request = URLRequest(url: Self.latestReleaseAPI)
                // GitHub's API rejects requests without a User-Agent.
                request.setValue("Glide-App", forHTTPHeaderField: "User-Agent")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 15

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    state = .failed
                    return
                }
                let release = try JSONDecoder().decode(Release.self, from: data)
                let url = URL(string: release.htmlURL) ?? URL(string: "https://github.com/Vatsal057/Glide/releases/latest")!
                if VersionCompare.isNewer(release.tagName, than: currentVersion) {
                    state = .available(version: release.tagName, url: url)
                } else {
                    state = .upToDate
                }
            } catch {
                state = .failed
            }
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
