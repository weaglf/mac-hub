import Foundation

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock, weather, spotify, steam, battery, memory, note, calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: "Saat"
        case .weather: "Hava Durumu"
        case .spotify: "Şu An Çalan"
        case .steam: "Steam Oyunları"
        case .battery: "Pil"
        case .memory: "Hub Belleği"
        case .note: "Not"
        case .calendar: "Takvim"
        }
    }

    var summary: String {
        switch self {
        case .clock: "Büyük saat ve tarih"
        case .weather: "Anlık sıcaklık ve gün tahmini"
        case .spotify: "Spotify'da çalan şarkı, kontrol"
        case .steam: "Yüklü ve son oynanan oyunlar"
        case .battery: "Şarj durumu"
        case .memory: "Hub'ın ve açık web servislerinin RAM kullanımı"
        case .note: "Kısa bir not"
        case .calendar: "Yaklaşan etkinlikler"
        }
    }

    var symbol: String {
        switch self {
        case .clock: "clock.fill"
        case .weather: "cloud.sun.fill"
        case .spotify: "music.note"
        case .steam: "gamecontroller.fill"
        case .battery: "battery.100percent.bolt"
        case .memory: "memorychip"
        case .note: "note.text"
        case .calendar: "calendar"
        }
    }

    var isWide: Bool {
        switch self {
        case .spotify, .steam, .calendar: true
        default: false
        }
    }
}

struct WidgetInstance: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: WidgetKind
    var text: String = ""
}

enum WebMode: String, Codable, CaseIterable {
    case inApp, browser
}

struct HubSettings: Codable, Equatable {
    var city = "İstanbul"
    var webMode: WebMode = .inApp
    /// Ana satırda gösterilmeyen uygulamaların kimlikleri (ör. "steam").
    var hiddenTiles: Set<String> = []
    /// Ana ekrana dönünce web servisi arka planda açık kalsın mı (kaldığın yerden devam için).
    var keepWebOpen = true
    /// Hub öndeyken Dock hiç görünmesin (kapalıysa ekranın altına gelince açılır).
    var hideDock = false
    /// Başka bir uygulamaya geçince Hub penceresi saklansın (arkada görünmesin).
    var hideWhenInactive = true

    init() {}

    /// Eksik alanlar varsayılanı alır; yeni bir ayar eklenince eski config.json bozulmasın.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HubSettings()
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? d.city
        webMode = (try? c.decodeIfPresent(WebMode.self, forKey: .webMode)) ?? d.webMode
        hiddenTiles = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenTiles) ?? d.hiddenTiles
        keepWebOpen = try c.decodeIfPresent(Bool.self, forKey: .keepWebOpen) ?? d.keepWebOpen
        hideDock = try c.decodeIfPresent(Bool.self, forKey: .hideDock) ?? d.hideDock
        hideWhenInactive = try c.decodeIfPresent(Bool.self, forKey: .hideWhenInactive) ?? d.hideWhenInactive
    }
}

struct HubConfig: Codable {
    var widgets: [WidgetInstance]
    var settings: HubSettings

    init(widgets: [WidgetInstance], settings: HubSettings) {
        self.widgets = widgets
        self.settings = settings
    }

    /// Tanınmayan widget'lar (ör. kaldırılmış bir türden) atlanır; düzenin geri kalanı ve notlar korunur.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let items = try c.decodeIfPresent([Lossy<WidgetInstance>].self, forKey: .widgets)
        widgets = items?.compactMap(\.value) ?? HubConfig.default.widgets
        settings = (try? c.decodeIfPresent(HubSettings.self, forKey: .settings)) ?? HubSettings()
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    static let `default` = HubConfig(
        widgets: [
            WidgetInstance(kind: .weather),
            WidgetInstance(kind: .spotify),
            WidgetInstance(kind: .battery),
        ],
        settings: HubSettings()
    )

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Hub", isDirectory: true).appendingPathComponent("config.json")
    }

    static func load() -> HubConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(HubConfig.self, from: data) else { return .default }
        return config
    }

    func save() {
        let url = HubConfig.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
