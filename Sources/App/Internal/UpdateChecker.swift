import AppKit
import Foundation

/// Checks GitHub Releases for a newer Glide, then downloads and installs it
/// in place. No Sparkle, no appcast, no trip to the website.
///
/// The whole flow lives in one state machine so the UI can render every stage
/// from a single `state` value:
///
///   idle → checking → available → downloading → installing → installed → (relaunch)
///
/// Any step can fall to `.failed`, and a download that can't be self-installed
/// (read-only location, no write access to the parent folder) falls back to
/// `.manualInstall`, which hands the user the already-downloaded disk image.
@MainActor
final class UpdateChecker: ObservableObject {

    /// Shared so the menu bar and the Preferences window agree on what's going on.
    static let shared = UpdateChecker()

    // MARK: - State

    struct Update: Equatable {
        /// Release tag, e.g. `v2.1.0`.
        let tag: String
        /// Tag without the leading `v`, for display next to the running version.
        let version: String
        /// The release page, used for notes and as the manual-download fallback.
        let pageURL: URL
        /// Direct link to the `.dmg`, when the release publishes one.
        let dmgURL: URL?
        /// Direct link to the published `shasum` file, when there is one.
        let checksumURL: URL?
        /// Asset size in bytes, `0` when unknown.
        let size: Int64

        var canSelfInstall: Bool { dmgURL != nil }
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Update)
        /// `fraction` is 0…1, or `nil` when the server didn't send a length.
        case downloading(fraction: Double?)
        case installing
        case installed(version: String)
        /// Downloaded fine, but Glide couldn't replace itself.
        case manualInstall(dmg: URL, reason: String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .installing: return true
            default: return false
            }
        }
    }

    @Published private(set) var state: State = .idle

    // MARK: - Config

    private static let latestReleaseAPI =
        URL(string: "https://api.github.com/repos/Vatsal057/Glide/releases/latest")!
    private static let releasesPage =
        URL(string: "https://github.com/Vatsal057/Glide/releases/latest")!

    /// How long a "you're up to date" answer stays good enough for the
    /// automatic check that runs when Preferences opens.
    private static let autoCheckInterval: TimeInterval = 6 * 60 * 60

    private var lastCheck: Date?
    private var downloadedDMG: URL?
    private var installedApp: URL?

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Check

    /// Checks at most once per `autoCheckInterval`, and never while something
    /// is already in flight or an update is already waiting.
    func checkIfDue() {
        switch state {
        case .idle, .upToDate, .failed:
            break
        default:
            return
        }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Self.autoCheckInterval { return }
        check()
    }

    func check() {
        guard !state.isBusy else { return }
        state = .checking

        Task {
            do {
                let release = try await fetchLatestRelease()
                lastCheck = Date()

                guard VersionCompare.isNewer(release.tag, than: currentVersion) else {
                    state = .upToDate
                    return
                }
                state = .available(release)
            } catch {
                AppLogger.debug("[update] check failed: \(error.localizedDescription)")
                state = .failed("Couldn't reach GitHub right now.")
            }
        }
    }

    // MARK: - Download + install

    /// Downloads the release disk image and installs it over the running app.
    func downloadAndInstall(_ update: Update) {
        guard !state.isBusy else { return }

        guard let dmgURL = update.dmgURL else {
            // Nothing to install — this release has no disk image attached.
            NSWorkspace.shared.open(update.pageURL)
            return
        }

        state = .downloading(fraction: 0)

        Task {
            let dmg: URL
            do {
                dmg = try await download(dmgURL, expectedSize: update.size)
            } catch {
                AppLogger.debug("[update] download failed: \(error)")
                state = .failed(Self.friendlyMessage(for: error))
                return
            }
            downloadedDMG = dmg

            // Integrity check against the checksum published beside the image.
            //
            // Glide is ad-hoc signed, so `codesign --verify` only proves the
            // bundle is internally consistent — it can't prove the bundle is
            // *ours*. This digest is the only real authenticity control in the
            // pipeline, so once a release publishes one, a failure to check it
            // has to abort. Releases with no checksum asset at all still
            // install (older versions shipped without one), but a checksum
            // that exists and can't be fetched or doesn't match does not.
            if let checksumURL = update.checksumURL {
                do {
                    let expected = try await fetchText(checksumURL)
                    let digest = try await Task.detached { try UpdateInstaller.sha256(ofFileAt: dmg) }.value
                    guard UpdateInstaller.checksumMatches(digest, publishedLine: expected) else {
                        try? FileManager.default.removeItem(at: dmg)
                        downloadedDMG = nil
                        state = .failed(UpdateInstaller.Failure.checksumMismatch.localizedDescription)
                        return
                    }
                    AppLogger.debug("[update] checksum verified")
                } catch {
                    AppLogger.debug("[update] checksum fetch failed: \(error.localizedDescription)")
                    try? FileManager.default.removeItem(at: dmg)
                    downloadedDMG = nil
                    state = .failed("Couldn't verify the download against its published checksum. Nothing was installed.")
                    return
                }
            }

            state = .installing

            let destination = Bundle.main.bundleURL
            let current = currentVersion
            let bundleID = Bundle.main.bundleIdentifier

            do {
                let imageVersion = try await Task.detached {
                    try UpdateInstaller.install(
                        dmg: dmg,
                        into: destination,
                        currentVersion: current,
                        expectedBundleID: bundleID
                    )
                }.value
                AppLogger.debug("[update] installed image reports version \(imageVersion)")

                try? FileManager.default.removeItem(at: dmg)
                downloadedDMG = nil
                installedApp = destination
                // The release tag is what the user was offered, so that's what
                // gets reported back — the image's own plist can lag it.
                state = .installed(version: update.version)

            } catch let failure as UpdateInstaller.Failure {
                AppLogger.debug("[update] install failed: \(failure.localizedDescription)")
                state = .manualInstall(dmg: dmg, reason: failure.localizedDescription)
            } catch {
                AppLogger.debug("[update] install failed: \(error.localizedDescription)")
                state = .manualInstall(dmg: dmg, reason: error.localizedDescription)
            }
        }
    }

    /// Quits and reopens the freshly installed copy.
    func relaunch() {
        UpdateInstaller.relaunch(installedApp ?? Bundle.main.bundleURL)
    }

    /// Reveals the downloaded image in Finder for the manual-install fallback.
    ///
    /// `NSWorkspace.open` would mount the image instead of showing it, which
    /// isn't what the button says and leaves a volume attached.
    func revealDownload(_ dmg: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([dmg])
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesPage)
    }

    func dismiss() {
        guard !state.isBusy else { return }
        if let downloadedDMG { try? FileManager.default.removeItem(at: downloadedDMG) }
        downloadedDMG = nil
        state = .idle
    }

    // MARK: - Networking

    /// `URLError.localizedDescription` bottoms out at things like
    /// "NSURLErrorDomain error -1011", which is no help in a settings pane.
    private static func friendlyMessage(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return "Download failed. \(error.localizedDescription)"
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return "Download failed — no connection to GitHub."
        case .timedOut:
            return "The download timed out. Try again."
        case .cancelled:
            return "The download was cancelled."
        case .cannotWriteToFile, .cannotCreateFile:
            return "Couldn't save the download to disk."
        default:
            return "GitHub didn't return the download. Try again in a moment."
        }
    }

    private func fetchLatestRelease() async throws -> Update {
        var request = URLRequest(url: Self.latestReleaseAPI)
        // GitHub's API rejects requests without a User-Agent.
        request.setValue("Glide-App", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(Release.self, from: data)
        let assets = release.assets ?? []

        let dmg = assets.first { $0.name.lowercased().hasSuffix(".dmg") }
        let checksum = assets.first { $0.name.lowercased().hasSuffix(".sha256") }

        return Update(
            tag: release.tagName,
            version: release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName,
            pageURL: Self.trustedURL(release.htmlURL) ?? Self.releasesPage,
            dmgURL: dmg.flatMap { Self.trustedURL($0.browserDownloadURL) },
            checksumURL: checksum.flatMap { Self.trustedURL($0.browserDownloadURL) },
            size: dmg?.size ?? 0
        )
    }

    /// Hosts an update artifact or release page is allowed to live on.
    private static let allowedHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
        "codeload.github.com",
    ]

    /// Accepts a URL from the release JSON only if it's HTTPS on a GitHub host.
    ///
    /// These strings arrive from a remote server and then get downloaded,
    /// installed over the running app, or handed to `NSWorkspace.open`. Without
    /// a check, a `file:` or `http:` URL — or a redirect to somewhere else
    /// entirely — would be followed just as readily as a real release asset.
    static func trustedURL(_ candidate: String) -> URL? {
        guard let url = URL(string: candidate),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return nil }
        guard allowedHosts.contains(host) || host.hasSuffix(".githubusercontent.com") else {
            AppLogger.debug("[update] rejected non-GitHub URL host: \(host)")
            return nil
        }
        return url
    }

    private func fetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Glide-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            throw URLError(.badServerResponse)
        }
        return text
    }

    private func download(_ url: URL, expectedSize: Int64) async throws -> URL {
        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Glide-update-\(UUID().uuidString).dmg")

        return try await FileDownload.run(
            url: url,
            to: destination,
            expectedSize: expectedSize
        ) { [weak self] fraction in
            guard let self else { return }
            // Ignore late progress once the download has moved on.
            if case .downloading = self.state {
                self.state = .downloading(fraction: fraction)
            }
        }
    }

    // MARK: - Wire format

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        let size: Int64

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }
    }
}

// MARK: - File download

/// A download task that reports progress and writes to a path we choose.
///
/// `URLSession`'s async `download(for:delegate:)` owns the temporary file and
/// its progress reporting is awkward to hook, so this drives a delegate-backed
/// session directly: progress on every chunk, the finished file moved into
/// place synchronously before the delegate returns, and a single resumption of
/// the continuation either way.
final class FileDownload: NSObject, URLSessionDownloadDelegate {

    static func run(
        url: URL,
        to destination: URL,
        expectedSize: Int64,
        onProgress: @escaping @MainActor (Double?) -> Void
    ) async throws -> URL {
        let downloader = FileDownload(destination: destination, expectedSize: expectedSize, onProgress: onProgress)
        return try await downloader.start(url: url)
    }

    private let destination: URL
    private let expectedSize: Int64
    private let onProgress: @MainActor (Double?) -> Void

    private var session: URLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var savedURL: URL?
    private var saveError: Error?
    private var lastReportedPercent: Int = -1

    private init(
        destination: URL,
        expectedSize: Int64,
        onProgress: @escaping @MainActor (Double?) -> Void
    ) {
        self.destination = destination
        self.expectedSize = expectedSize
        self.onProgress = onProgress
        super.init()
    }

    private func start(url: URL) async throws -> URL {
        // A serial delegate queue means the delegate callbacks below never
        // race each other, so the mutable state above needs no locking.
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = 15 * 60

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue("Glide-App", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        defer { session.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: request).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        let fraction: Double? = total > 0
            ? min(1, Double(totalBytesWritten) / Double(total))
            : nil

        // Throttle to whole percentage points — SwiftUI doesn't need 4,000
        // republishes for one download.
        let percent = fraction.map { Int($0 * 100) } ?? -1
        guard percent != lastReportedPercent else { return }
        lastReportedPercent = percent

        Task { @MainActor [onProgress] in onProgress(fraction) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The file at `location` is deleted as soon as this method returns, so
        // the move has to happen here and now.
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            saveError = URLError(.badServerResponse)
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            savedURL = destination
        } catch {
            saveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else if let saveError {
            finish(.failure(saveError))
        } else if let savedURL {
            finish(.success(savedURL))
        } else {
            finish(.failure(URLError(.cannotWriteToFile)))
        }
    }
}
