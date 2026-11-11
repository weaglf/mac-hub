import Foundation
import Observation

struct SteamGame: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let lastPlayed: Date?
    /// Steam'in kendi önbelleğindeki kapak (varsa).
    let localPoster: URL?
    let localHeader: URL?

    var posterURL: URL { localPoster ?? URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/library_600x900.jpg")! }
    var headerURL: URL { localHeader ?? URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/header.jpg")! }
    var heroURL: URL { URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(id)/library_hero.jpg")! }
    var runURL: URL { URL(string: "steam://rungameid/\(id)")! }
}

/// Yüklü Steam oyunlarını Steam'in yerel dosyalarından okur.
@Observable @MainActor
final class SteamService {
    nonisolated static let bundleIDs = ["com.valvesoftware.steam"]
    var games: [SteamGame] = []

    func refresh() {
        Task.detached(priority: .utility) {
            let found = Self.scan()
            await MainActor.run { self.games = found }
        }
    }

    nonisolated private static func scan() -> [SteamGame] {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam")
        let cache = root.appendingPathComponent("appcache/librarycache")
        var libraries = [root.path]
        if let vdf = try? String(contentsOf: root.appendingPathComponent("steamapps/libraryfolders.vdf"), encoding: .utf8) {
            libraries += matches(in: vdf, key: "path")
        }

        var games: [String: SteamGame] = [:]
        for library in Set(libraries) {
            let apps = URL(fileURLWithPath: library).appendingPathComponent("steamapps")
            guard let files = try? fm.contentsOfDirectory(atPath: apps.path) else { continue }
            for file in files where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
                guard let text = try? String(contentsOf: apps.appendingPathComponent(file), encoding: .utf8),
                      let id = matches(in: text, key: "appid").first,
                      let name = matches(in: text, key: "name").first else { continue }
                // Steam'in kendi bileşenlerini (Proton, redistributable vb.) gösterme.
                if ["228980", "1070560", "1391110", "1628350"].contains(id) || name.contains("Steamworks") { continue }
                let lastPlayed = matches(in: text, key: "LastPlayed").first.flatMap(TimeInterval.init)
                    .flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                let poster = cache.appendingPathComponent("\(id)/library_600x900.jpg")
                let header = cache.appendingPathComponent("\(id)/header.jpg")
                games[id] = SteamGame(
                    id: id, name: name, lastPlayed: lastPlayed,
                    localPoster: fm.fileExists(atPath: poster.path) ? poster : nil,
                    localHeader: fm.fileExists(atPath: header.path) ? header : nil
                )
            }
        }
        return games.values.sorted {
            switch ($0.lastPlayed, $1.lastPlayed) {
            case let (a?, b?): a > b
            case (_?, nil): true
            case (nil, _?): false
            default: $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    /// VDF içinde "key"  "value" çiftlerini bulur.
    nonisolated private static func matches(in text: String, key: String) -> [String] {
        let pattern = "\"\(key)\"\\s+\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]).replacingOccurrences(of: "\\\\", with: "\\") }
        }
    }
}
