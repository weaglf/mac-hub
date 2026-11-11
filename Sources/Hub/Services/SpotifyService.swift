import AppKit
import Observation

/// Spotify'ın yayınladığı dağıtık bildirimleri dinler (izin gerektirmez);
/// oynat/duraklat gibi komutları AppleScript ile gönderir (ilk seferde macOS izin sorar).
@Observable @MainActor
final class SpotifyService {
    enum Command { case playPause, next, previous }

    nonisolated static let bundleIDs = ["com.spotify.client"]

    var isRunning = false
    var isPlaying = false
    var track: String?
    var artist: String?
    var album: String?
    var trackID: String?
    var artworkURL: URL?
    var duration: Double = 0
    private var position: Double = 0
    private var positionDate = Date()

    var allowAppleScript = true

    var hasTrack: Bool { isRunning && track != nil }

    func currentPosition(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(positionDate))
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.apply(info) }
        }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == "com.spotify.client" else { return }
                MainActor.assumeIsolated {
                    self?.isRunning = name == NSWorkspace.didLaunchApplicationNotification
                    if self?.isRunning == false { self?.clear() }
                }
            }
        }

        isRunning = Launcher.runningApp(Self.bundleIDs) != nil
        Task { await refresh() }
    }

    private func clear() {
        isPlaying = false
        track = nil
        artist = nil
        album = nil
        trackID = nil
        artworkURL = nil
        duration = 0
        position = 0
    }

    private func apply(_ info: [AnyHashable: Any]) {
        isRunning = true
        let state = info["Player State"] as? String
        if state == "Stopped" { clear(); return }
        isPlaying = state == "Playing"
        track = info["Name"] as? String ?? track
        artist = info["Artist"] as? String ?? artist
        album = info["Album"] as? String ?? album
        if let ms = (info["Duration"] as? NSNumber)?.doubleValue { duration = ms / 1000 }
        position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? position
        positionDate = Date()

        let id = info["Track ID"] as? String
        if id != trackID {
            trackID = id
            artworkURL = nil
            if let id { Task { await fetchArtwork(trackID: id) } }
        }
    }

    /// Spotify açıksa durumu AppleScript ile okur.
    func refresh() async {
        guard allowAppleScript, Launcher.runningApp(Self.bundleIDs) != nil else { return }
        let script = """
        tell application "Spotify"
            set s to player state as string
            if s is "stopped" then return "stopped"
            set t to current track
            return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (id of t) & linefeed & (artwork url of t) & linefeed & (player position as string) & linefeed & ((duration of t) as string)
        end tell
        """
        guard let output = await AppleScript.run(script) else { return }
        let lines = output.components(separatedBy: "\n")
        isRunning = true
        guard lines.count >= 8 else { clear(); return }
        isPlaying = lines[0] == "playing"
        track = lines[1]
        artist = lines[2]
        album = lines[3]
        trackID = lines[4]
        artworkURL = URL(string: lines[5])
        position = Double(lines[6].replacingOccurrences(of: ",", with: ".")) ?? 0
        positionDate = Date()
        duration = (Double(lines[7]) ?? 0) / 1000
    }

    func send(_ command: Command) {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        Task {
            _ = await AppleScript.run("tell application \"Spotify\" to \(verb)")
            try? await Task.sleep(for: .milliseconds(350))
            await refresh()
        }
    }

    /// Kapak görselini Spotify oEmbed üzerinden bulur (giriş gerektirmez).
    private func fetchArtwork(trackID: String) async {
        let parts = trackID.split(separator: ":")
        guard parts.count == 3,
              let url = URL(string: "https://open.spotify.com/oembed?url=https://open.spotify.com/\(parts[1])/\(parts[2])")
        else { return }
        struct OEmbed: Decodable { let thumbnail_url: String? }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let embed = try? JSONDecoder().decode(OEmbed.self, from: data),
              let thumb = embed.thumbnail_url,
              self.trackID == trackID else { return }
        artworkURL = URL(string: thumb)
    }
}

enum AppleScript {
    /// osascript'i arka planda çalıştırır; başarısızsa nil.
    nonisolated static func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]
                let out = Pipe()
                process.standardOutput = out
                process.standardError = Pipe()
                do { try process.run() } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text)
            }
        }
    }
}
