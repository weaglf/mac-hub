import SwiftUI

/// Ana satırdaki bir uygulama kutusu.
struct Tile: Identifiable, Hashable {
    enum Logo: Hashable {
        case appIcon(fallback: String)
        case netflix, youtube, appleTV, prime, tvplus, twitch, reddit
    }

    let id: String
    let name: String
    let tagline: String
    let accent: Color
    let background: [Color]
    let logo: Logo
    /// Yerel uygulama (varsa) — seçilince açılır.
    var bundleIDs: [String] = []
    /// Web servisi ana sayfası — seçilince Hub içinde (veya tarayıcıda) açılır.
    var webURL: URL? = nil
    /// Uygulama kurulu değilse açılacak adres.
    var fallbackURL: URL? = nil

    static func == (lhs: Tile, rhs: Tile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Tile {
    static let all: [Tile] = [
        Tile(id: "steam", name: "Steam", tagline: "Oyun kütüphanen",
             accent: Color(hex: 0x66C0F4), background: [Color(hex: 0x0B1422), Color(hex: 0x1B2838), Color(hex: 0x2A475E)],
             logo: .appIcon(fallback: "STEAM"),
             bundleIDs: ["com.valvesoftware.steam"], fallbackURL: URL(string: "https://store.steampowered.com")),
        Tile(id: "netflix", name: "Netflix", tagline: "Diziler ve filmler",
             accent: Color(hex: 0xE50914), background: [Color(hex: 0x000000), Color(hex: 0x1A0506)],
             logo: .netflix, webURL: URL(string: "https://www.netflix.com/browse")),
        Tile(id: "appletv", name: "Apple TV", tagline: "Apple TV+, filmler ve diziler",
             accent: Color(hex: 0xB8C4D6), background: [Color(hex: 0x1C1C1E), Color(hex: 0x3A3A3C)],
             logo: .appleTV, bundleIDs: ["com.apple.TV"], fallbackURL: URL(string: "https://tv.apple.com")),
        Tile(id: "prime", name: "Prime Video", tagline: "Amazon Prime Video",
             accent: Color(hex: 0x00A8E1), background: [Color(hex: 0x0F171E), Color(hex: 0x00405A)],
             logo: .prime, bundleIDs: ["com.amazon.aiv.AIVApp"], fallbackURL: URL(string: "https://www.primevideo.com")),
        Tile(id: "tvplus", name: "TV+", tagline: "Canlı TV, dizi ve film",
             accent: Color(hex: 0xFAD604), background: [Color(hex: 0x0A0A0A), Color(hex: 0x262626)],
             logo: .tvplus, webURL: URL(string: "https://tvplus.com.tr")),
        Tile(id: "youtube", name: "YouTube", tagline: "Videolar ve abonelikler",
             accent: Color(hex: 0xFF0033), background: [Color(hex: 0x0F0F0F), Color(hex: 0x272727)],
             logo: .youtube, webURL: URL(string: "https://www.youtube.com")),
        Tile(id: "twitch", name: "Twitch", tagline: "Canlı yayınlar",
             accent: Color(hex: 0x9146FF), background: [Color(hex: 0x4B2A8C), Color(hex: 0x9146FF)],
             logo: .twitch, webURL: URL(string: "https://www.twitch.tv")),
        Tile(id: "spotify", name: "Spotify", tagline: "Müzik ve podcast",
             accent: Color(hex: 0x1DB954), background: [Color(hex: 0x121212), Color(hex: 0x0E3B21)],
             logo: .appIcon(fallback: "Spotify"),
             bundleIDs: ["com.spotify.client"], fallbackURL: URL(string: "https://open.spotify.com")),
        Tile(id: "reddit", name: "Reddit", tagline: "Topluluklar",
             accent: Color(hex: 0xFF4500), background: [Color(hex: 0xE03D00), Color(hex: 0xFF6A33)],
             logo: .reddit, webURL: URL(string: "https://www.reddit.com")),
    ]
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
