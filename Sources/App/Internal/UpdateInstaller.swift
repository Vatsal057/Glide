import AppKit
import CryptoKit
import Foundation

/// Installs a downloaded Glide DMG over the running app bundle.
///
/// No Sparkle. The pipeline is deliberately boring and inspectable:
///
///   1. `hdiutil attach` the disk image at a private mount point.
///   2. Confirm the bundle inside is Glide, and is genuinely newer.
///   3. `codesign --verify` it so a truncated or tampered download can't be installed.
///   4. `ditto` it to a staging folder beside the destination (same volume).
///   5. Atomically swap it over the running bundle.
///   6. Detach, then relaunch from a detached shell that waits for us to exit.
///
/// Every step is reversible until step 5, and step 5 is a single atomic
/// replace, so a failure never leaves a half-written app behind.
enum UpdateInstaller {

    // MARK: - Errors

    enum Failure: LocalizedError, Equatable {
        case checksumMismatch
        case mountFailed(String)
        case appNotFoundInImage
        case wrongApp(String)
        case downgrade(image: String, running: String)
        case signatureInvalid(String)
        case destinationNotWritable(String)
        case stagingFailed(String)
        case swapFailed(String)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch:
                return "The download didn't match its published checksum."
            case .mountFailed(let detail):
                return "Couldn't open the downloaded disk image. \(detail)"
            case .appNotFoundInImage:
                return "The disk image didn't contain Glide.app."
            case .wrongApp(let found):
                return "The disk image contained \(found) instead of Glide."
            case .downgrade(let image, let running):
                return "The disk image contains version \(image), older than the installed \(running)."
            case .signatureInvalid(let detail):
                return "The downloaded app failed signature verification. \(detail)"
            case .destinationNotWritable(let path):
                return "Glide can't update itself at \(path). Install it manually instead."
            case .stagingFailed(let detail):
                return "Couldn't copy the new version into place. \(detail)"
            case .swapFailed(let detail):
                return "Couldn't replace the current version. \(detail)"
            }
        }
    }

    // MARK: - Checksum

    /// SHA-256 of a file, streamed so a large image never lands in memory.
    static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Compares a computed digest against a published `shasum`-style line,
    /// e.g. `d34db33f…  Glide-v2.1.0.dmg`.
    static func checksumMatches(_ digest: String, publishedLine: String) -> Bool {
        let published = publishedLine
            .split(whereSeparator: \.isWhitespace)
            .first
            .map { String($0).lowercased() }
        guard let published, published.count == 64 else { return false }
        return published == digest.lowercased()
    }

    // MARK: - Install

    /// Mounts `dmg`, validates the app inside it, and swaps it over `destination`.
    ///
    /// Runs off the main thread — it shells out and copies a few dozen megabytes.
    /// Returns the version string that was actually installed.
    static func install(
        dmg: URL,
        into destination: URL,
        currentVersion: String,
        expectedBundleID: String?
    ) throws -> String {

        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw Failure.destinationNotWritable(parent.path)
        }

        // ── 1. Mount at a private mount point ──────────────────────────
        let mountPoint = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glide-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attach = try shell("/usr/bin/hdiutil", [
            "attach", dmg.path,
            "-nobrowse",
            "-readonly",
            "-noverify",
            "-mountpoint", mountPoint.path,
        ])
        guard attach.status == 0 else {
            try? FileManager.default.removeItem(at: mountPoint)
            throw Failure.mountFailed(attach.combinedOutput)
        }

        defer {
            detach(mountPoint)
            try? FileManager.default.removeItem(at: mountPoint)
        }

        // ── 2. Locate the app inside the image ─────────────────────────
        guard let sourceApp = locateApp(in: mountPoint) else {
            throw Failure.appNotFoundInImage
        }

        let info = Bundle(url: sourceApp)?.infoDictionary ?? [:]

        if let expectedBundleID {
            let foundID = info["CFBundleIdentifier"] as? String ?? "unknown"
            guard foundID == expectedBundleID else { throw Failure.wrongApp(foundID) }
        }

        // Whether this release is newer was already settled by comparing release
        // tags. The version baked into the image is only trusted far enough to
        // refuse an outright downgrade — releases have shipped with a plist
        // version that lags their tag (v2.0.0's image says "2.0"), and treating
        // that as "not newer" would block a perfectly good update.
        let newVersion = info["CFBundleShortVersionString"] as? String ?? ""
        if !newVersion.isEmpty, VersionCompare.isNewer(currentVersion, than: newVersion) {
            throw Failure.downgrade(image: newVersion, running: currentVersion)
        }

        // ── 3. Verify the code signature ───────────────────────────────
        //
        // Glide ships ad-hoc signed (it isn't notarized), and `--verify`
        // still checks every sealed resource against the bundle's own
        // signature — which is exactly the tamper/truncation check we want.
        let verify = try shell("/usr/bin/codesign", ["--verify", "--deep", "--strict", sourceApp.path])
        guard verify.status == 0 else {
            throw Failure.signatureInvalid(verify.combinedOutput)
        }

        // ── 4. Stage beside the destination, on the same volume ────────
        let staging = parent.appendingPathComponent(".glide-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let stagedApp = staging.appendingPathComponent(destination.lastPathComponent)

        // `ditto` preserves symlinks, permissions and extended attributes
        // inside the bundle, which a naive recursive copy does not.
        let copy = try shell("/usr/bin/ditto", [sourceApp.path, stagedApp.path])
        guard copy.status == 0 else {
            throw Failure.stagingFailed(copy.combinedOutput)
        }

        // Clear any quarantine flag that rode along inside the image, so the
        // relaunched copy doesn't trip Gatekeeper.
        _ = try? shell("/usr/bin/xattr", ["-cr", stagedApp.path])

        // ── 5. Atomic swap ─────────────────────────────────────────────
        try swap(stagedApp, over: destination)

        return newVersion
    }

    /// Replaces `destination` with `staged`. Atomic when the platform allows it,
    /// with a move-based fallback for volumes where it doesn't.
    private static func swap(_ staged: URL, over destination: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(
                destination,
                withItemAt: staged,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
            return
        } catch {
            // Fall through to the manual path below.
            AppLogger.debug("[update] atomic replace failed: \(error.localizedDescription)")
        }

        // Fallback: park the old bundle aside, move the new one in, then bin
        // the old one. Ordering matters — the new copy is in place before the
        // old one is deleted, so a crash mid-way still leaves a working app.
        let parked = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".glide-old-\(UUID().uuidString).app")
        do {
            try FileManager.default.moveItem(at: destination, to: parked)
        } catch {
            throw Failure.swapFailed(error.localizedDescription)
        }
        do {
            try FileManager.default.moveItem(at: staged, to: destination)
        } catch {
            try? FileManager.default.moveItem(at: parked, to: destination)
            throw Failure.swapFailed(error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: parked)
    }

    // MARK: - Relaunch

    /// Relaunches `app` and quits the current instance.
    ///
    /// A detached `sh` waits for this process to actually exit before calling
    /// `open`, otherwise LaunchServices just reactivates the dying instance.
    @MainActor
    static func relaunch(_ app: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        # Wait for Glide to exit (capped, so this never becomes a stray process).
        i=0
        while /bin/kill -0 \(pid) 2>/dev/null; do
            /bin/sleep 0.2
            i=$((i + 1))
            [ "$i" -gt 150 ] && break
        done
        /bin/sleep 0.3
        /usr/bin/open \(shellQuoted(app.path))
        /bin/rm -f "$0"
        """

        let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glide-relaunch-\(UUID().uuidString).sh")

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptURL.path]
            try process.run()
        } catch {
            // Couldn't stage the relaunch — leave the app running rather than
            // quitting into nothing. The new version is already installed and
            // will be picked up on the next manual launch.
            AppLogger.debug("[update] relaunch helper failed: \(error.localizedDescription)")
            return
        }

        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private static func locateApp(in mountPoint: URL) -> URL? {
        let fm = FileManager.default
        let expected = mountPoint.appendingPathComponent("Glide.app")
        if fm.fileExists(atPath: expected.path) { return expected }

        let contents = (try? fm.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.first { $0.pathExtension == "app" }
    }

    private static func detach(_ mountPoint: URL) {
        let quiet = try? shell("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"])
        if quiet?.status != 0 {
            _ = try? shell("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"])
        }
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private struct ShellResult {
        let status: Int32
        let stdout: String
        let stderr: String

        /// Tool output boiled down to something worth showing a user.
        ///
        /// `hdiutil` and friends emit deprecation notices on newer macOS that
        /// have nothing to do with why a step failed, and pasting them into an
        /// error label is just noise.
        var combinedOutput: String {
            let lines = (stderr + "\n" + stdout)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { line in
                    guard !line.isEmpty else { return false }
                    let lowered = line.lowercased()
                    return !lowered.contains("is deprecated")
                        && !lowered.contains("warning:")
                }

            let joined = lines.joined(separator: " ")
            return joined.count > 200 ? String(joined.prefix(200)) + "…" : joined
        }
    }

    /// Runs a tool with an argument array — never a composed command string —
    /// so paths with spaces or quotes can't turn into extra arguments.
    private static func shell(_ launchPath: String, _ arguments: [String]) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // Drain both pipes before waiting, or a chatty tool can fill the
        // 64 KB pipe buffer and deadlock against waitUntilExit().
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ShellResult(
            status: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
