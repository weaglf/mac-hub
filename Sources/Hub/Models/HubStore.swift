import AppKit
import SwiftUI
import Observation

enum FocusArea { case shelf, apps, widgets }
enum Overlay: Equatable { case picker, settings }
enum InputAction { case up, down, left, right, select, back, delete, moveLeft, moveRight }
enum WebCommand { case back, forward, reload, openInBrowser }
enum HomeRow: Hashable { case shelf, apps, widgets }

/// Fare ekran kenarına dayanınca hangi satır hangi yöne kayıyor (-1 sol, 1 sağ).
struct EdgeScroll: Equatable {
    let row: HomeRow
    let direction: Int
}

struct WebSession: Identifiable, Equatable {
    let id = UUID()
    let tileID: String
    let title: String
    let url: URL?       // nil → kaldığın yerden devam
    let homeURL: URL
}

enum HubCommand {
    case launchApp([String], fallback: URL?)
    case web(URL, tileID: String)
    case external(URL)
    case spotify(SpotifyService.Command)
    case settings
    case resumeWeb(String)
    case closeWeb(String)
}

struct ShelfItem: Identifiable {
    enum Style {
        case action(symbol: String)
        case message(symbol: String)
        case poster(SteamGame)
        case nowPlaying
    }
    let id: String
    let title: String
    var subtitle: String? = nil
    let style: Style
    let command: HubCommand?
}

@Observable @MainActor
final class HubStore {
    /// Ayarlardan gizlenmeyen uygulamalar. Hepsi gizlenirse liste boş kalmasın diye tamamı döner.
    var tiles: [Tile] { Self.visibleTiles(hidden: settings.hiddenTiles) }

    private static func visibleTiles(hidden: Set<String>) -> [Tile] {
        let visible = Tile.all.filter { !hidden.contains($0.id) }
        return visible.isEmpty ? Tile.all : visible
    }

    // Odak
    var area: FocusArea = .apps
    var appIndex = 0
    var shelfIndex = 0
    var widgetIndex = 0
    var pickerIndex = 0
    var overlay: Overlay?
    var webSession: WebSession? { didSet { if (oldValue == nil) != (webSession == nil) { onPresentationChange?() } } }
    var editingNoteID: UUID?
    /// Arka planda açık duran web servisleri (kutunun altında nokta gösterilir).
    var openWebTiles: Set<String> = []

    // Ortam
    var isActive = true
    var snapshotMode = false
    var screenSize = CGSize(width: 1470, height: 956)
    var safeTop: CGFloat = 0
    /// Satırların ekrandaki yeri (kenar kaydırmada imlecin hangi satırda olduğunu bulmak için).
    @ObservationIgnored var rowFrames: [HomeRow: CGRect] = [:]
    var edgeScroll: EdgeScroll?
    @ObservationIgnored var onSummon: (() -> Void)?
    /// Dock/menü çubuğu görünürlüğü değişmeli (web açıldı/kapandı ya da ayar değişti).
    @ObservationIgnored var onPresentationChange: (() -> Void)?

    // Kalıcı ayarlar
    var widgets: [WidgetInstance] { didSet { persist() } }
    var settings: HubSettings { didSet { settingsChanged(from: oldValue) } }

    // Servisler
    let spotify = SpotifyService()
    let steam = SteamService()
    let weather = WeatherService()
    let system = SystemService()
    let calendar = CalendarService()
    let hubMemory = HubMemoryService()

    @ObservationIgnored private var launchedBundleIDs: Set<String> = []
    @ObservationIgnored private var timers: [Task<Void, Never>] = []

    init() {
        let config = HubConfig.load()
        widgets = config.widgets
        settings = config.settings
    }

    var currentTile: Tile {
        let list = tiles
        return list[min(max(0, appIndex), list.count - 1)]
    }

    var tileSize: CGSize {
        let width = min(300, max(180, (screenSize.width - 128) / 5.4 - 28)).rounded()
        return CGSize(width: width, height: (width * 0.58).rounded())
    }

    // MARK: - Yaşam döngüsü

    func start() {
        spotify.allowAppleScript = !snapshotMode
        spotify.start()
        steam.refresh()
        system.refresh()
        refreshHubMemory()
        observeWorkspace()
        Task { await weather.refresh(city: settings.city) }
        Task { await refreshCalendar(request: false) }

        timers = [
            repeating(every: 60) { self.system.refresh() },
            // Bellek widget'ı varsa ve Hub öndeyse 5 saniyede bir.
            repeating(every: 5) {
                if self.isActive, self.widgets.contains(where: { $0.kind == .memory }) { self.refreshHubMemory() }
            },
            // Başarılıysa 10 dakikada bir yeniler, hata varsa dakikada bir tekrar dener.
            repeating(every: 60) { await self.weather.refresh(city: self.settings.city) },
            repeating(every: 300) {
                self.steam.refresh()
                await self.refreshCalendar(request: false)
            },
        ]
    }

    func didBecomeActive() {
        steam.refresh()
        system.refresh()
        Task {
            await spotify.refresh()
            await weather.refresh(city: settings.city)
        }
    }

    private func repeating(every seconds: Double, _ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                await work()
            }
        }
    }

    func refreshHubMemory() {
        hubMemory.refresh(webProcesses: WebViewPool.shared.processIDs())
    }

    func refreshCalendar(request: Bool) async {
        guard widgets.contains(where: { $0.kind == .calendar }) else { return }
        await calendar.refresh(requestIfNeeded: request && !snapshotMode)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let id else { return }
                if self.launchedBundleIDs.remove(id) != nil { self.onSummon?() }
            }
        }
    }

    private func persist() {
        guard !snapshotMode else { return }
        HubConfig(widgets: widgets, settings: settings).save()
    }

    private func settingsChanged(from old: HubSettings) {
        persist()
        if old.hideDock != settings.hideDock { onPresentationChange?() }
        if old.hiddenTiles != settings.hiddenTiles {
            // Seçili uygulama görünür kaldıysa seçili kalsın; gizlendiyse yakınındakine geç.
            let oldList = Self.visibleTiles(hidden: old.hiddenTiles)
            let previousID = oldList.indices.contains(appIndex) ? oldList[appIndex].id : nil
            let list = tiles
            appIndex = list.firstIndex { $0.id == previousID } ?? min(appIndex, list.count - 1)
            shelfIndex = 0
        }
        if old.city != settings.city {
            Task { await weather.refresh(city: settings.city, force: true) }
        }
    }

    // MARK: - Gezinme

    func handle(_ action: InputAction, fromGamepad: Bool = false) {
        if webSession != nil {
            if fromGamepad, action == .back { goHome() }
            return
        }
        switch overlay {
        case .settings:
            if action == .back { overlay = nil }
            return
        case .picker:
            handlePicker(action)
            return
        case nil:
            break
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { navigate(action) }
    }

    private func navigate(_ action: InputAction) {
        switch area {
        case .apps:
            switch action {
            case .left: setApp(appIndex - 1)
            case .right: setApp(appIndex + 1)
            case .up:
                if !shelfItems.isEmpty { area = .shelf; shelfIndex = min(shelfIndex, shelfItems.count - 1) }
            case .down:
                area = .widgets
                widgetIndex = min(widgetIndex, widgets.count)
            case .select: activate(tile: currentTile)
            default: break
            }
        case .shelf:
            let items = shelfItems
            switch action {
            case .left: shelfIndex = max(0, shelfIndex - 1)
            case .right: shelfIndex = min(items.count - 1, shelfIndex + 1)
            case .down, .back: area = .apps
            case .select:
                if items.indices.contains(shelfIndex), let command = items[shelfIndex].command { perform(command) }
            default: break
            }
        case .widgets:
            switch action {
            case .left: widgetIndex = max(0, widgetIndex - 1)
            case .right: widgetIndex = min(widgets.count, widgetIndex + 1)
            case .up, .back: area = .apps
            case .select:
                if widgetIndex >= widgets.count { openPicker() } else { activate(widget: widgets[widgetIndex]) }
            case .delete: removeWidget(at: widgetIndex)
            case .moveLeft: moveWidget(at: widgetIndex, by: -1)
            case .moveRight: moveWidget(at: widgetIndex, by: 1)
            default: break
            }
        }
    }

    private func handlePicker(_ action: InputAction) {
        let kinds = WidgetKind.allCases
        let columns = 4
        switch action {
        case .left: pickerIndex = max(0, pickerIndex - 1)
        case .right: pickerIndex = min(kinds.count - 1, pickerIndex + 1)
        case .up: if pickerIndex - columns >= 0 { pickerIndex -= columns }
        case .down: if pickerIndex + columns < kinds.count { pickerIndex += columns }
        case .select: addWidget(kinds[pickerIndex])
        case .back: overlay = nil
        default: break
        }
    }

    private func setApp(_ index: Int) {
        let clamped = min(max(0, index), tiles.count - 1)
        guard clamped != appIndex else { return }
        appIndex = clamped
        shelfIndex = 0
    }

    /// Uygulama gizliyse false döner.
    @discardableResult
    private func jump(to tileID: String) -> Bool {
        guard let index = tiles.firstIndex(where: { $0.id == tileID }) else { return false }
        setApp(index)
        area = shelfItems.isEmpty ? .apps : .shelf
        return true
    }

    // Fare: üzerine gelmek hiçbir şeyi seçmez. Tıklama seçer; seçili öğeye tekrar tıklamak
    // (ya da çift tıklamak) açar. Tıklanan öğe kenara taşıyorsa satır onu görünür yapar.
    private func select(_ change: () -> Void) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { change() }
    }

    func clickApp(_ index: Int) {
        let alreadySelected = area == .apps && appIndex == index
        select { area = .apps; setApp(index) }
        if alreadySelected { activate(tile: currentTile) }
    }

    func clickShelf(_ index: Int) {
        let alreadySelected = area == .shelf && shelfIndex == index
        select { area = .shelf; shelfIndex = index }
        let items = shelfItems
        if alreadySelected, items.indices.contains(index), let command = items[index].command { perform(command) }
    }

    func clickWidget(_ index: Int) {
        let alreadySelected = area == .widgets && widgetIndex == index
        select { area = .widgets; widgetIndex = index }
        if alreadySelected, widgets.indices.contains(index) { activate(widget: widgets[index]) }
    }

    // MARK: - Eylemler

    func activate(tile: Tile) {
        if tile.webURL != nil { openWeb(url: nil, tile: tile); return }
        perform(.launchApp(tile.bundleIDs, fallback: tile.fallbackURL))
    }

    func perform(_ command: HubCommand) {
        switch command {
        case let .launchApp(ids, fallback):
            if Launcher.launch(ids) {
                launchedBundleIDs.formUnion(ids)
            } else if let fallback {
                openWeb(url: fallback, tile: currentTile)
            }
        case let .web(url, tileID):
            openWeb(url: url, tile: Tile.all.first { $0.id == tileID } ?? currentTile)
        case let .external(url):
            if url.scheme == "steam" { launchedBundleIDs.formUnion(SteamService.bundleIDs) }
            Launcher.open(url)
        case let .spotify(command):
            spotify.send(command)
        case .settings:
            toggleSettings()
        case let .resumeWeb(tileID):
            if let tile = Tile.all.first(where: { $0.id == tileID }) { openWeb(url: nil, tile: tile) }
        case let .closeWeb(tileID):
            closeWeb(tileID)
        }
    }

    func activate(widget: WidgetInstance) {
        switch widget.kind {
        case .spotify:
            if spotify.isRunning { spotify.send(.playPause) }
            else { perform(.launchApp(SpotifyService.bundleIDs, fallback: nil)) }
        case .steam: if !jump(to: "steam") { perform(.external(URL(string: "steam://open/games")!)) }
        case .note: editingNoteID = widget.id
        case .calendar: perform(.launchApp(["com.apple.iCal"], fallback: nil))
        case .weather: Task { await weather.refresh(city: settings.city, force: true) }
        case .clock: perform(.launchApp(["com.apple.clock"], fallback: nil))
        case .battery: break
        case .memory: perform(.launchApp(["com.apple.ActivityMonitor"], fallback: nil))
        }
    }

    // MARK: - Web

    func openWeb(url: URL?, tile: Tile) {
        guard let home = tile.webURL ?? tile.fallbackURL ?? url else { return }
        if settings.webMode == .browser {
            Launcher.open(url ?? home)
            return
        }
        withAnimation(snapshotMode ? nil : .easeInOut(duration: 0.25)) {
            webSession = WebSession(tileID: tile.id, title: tile.name, url: url, homeURL: home)
        }
        openWebTiles.insert(tile.id)
    }

    /// Ana ekrana döner. Ayara göre servis ya arka planda duraklatılmış bekler ya da kapanır.
    func goHome() {
        guard let session = webSession else { return }
        if settings.keepWebOpen {
            WebViewPool.shared.pause(session.tileID)
            withAnimation(snapshotMode ? nil : .easeInOut(duration: 0.25)) { webSession = nil }
        } else {
            closeWeb(session.tileID)
        }
    }

    /// Web servisini tamamen kapatır (sayfa, ses ve bellek serbest kalır).
    func closeWeb(_ tileID: String) {
        if webSession?.tileID == tileID {
            withAnimation(snapshotMode ? nil : .easeInOut(duration: 0.25)) { webSession = nil }
        }
        WebViewPool.shared.close(tileID)
        openWebTiles.remove(tileID)
        shelfIndex = min(shelfIndex, max(0, shelfItems.count - 1))
    }

    func closeCurrentWeb() {
        if let tileID = webSession?.tileID { closeWeb(tileID) }
    }

    func webCommand(_ command: WebCommand) {
        guard let session = webSession, let view = WebViewPool.shared.existing(session.tileID) else { return }
        switch command {
        case .back: view.goBack()
        case .forward: view.goForward()
        case .reload: view.reload()
        case .openInBrowser:
            if let url = view.url { Launcher.open(url) }
            goHome()
        }
    }

    // MARK: - Widget'lar ve paneller

    func openPicker() {
        pickerIndex = 0
        overlay = .picker
    }

    func toggleSettings() {
        overlay = overlay == .settings ? nil : .settings
    }

    func addWidget(_ kind: WidgetKind) {
        widgets.append(WidgetInstance(kind: kind))
        overlay = nil
        area = .widgets
        widgetIndex = widgets.count - 1
        switch kind {
        case .calendar: Task { await refreshCalendar(request: true) }
        case .memory: refreshHubMemory()
        case .steam: steam.refresh()
        default: break
        }
    }

    func removeWidget(at index: Int) {
        guard widgets.indices.contains(index) else { return }
        widgets.remove(at: index)
        widgetIndex = min(widgetIndex, widgets.count)
    }

    func removeWidget(id: UUID) {
        if let index = widgets.firstIndex(where: { $0.id == id }) { removeWidget(at: index) }
    }

    func moveWidget(at index: Int, by delta: Int) {
        let target = index + delta
        guard widgets.indices.contains(index), widgets.indices.contains(target) else { return }
        widgets.swapAt(index, target)
        widgetIndex = target
    }

    func moveWidget(id: UUID, by delta: Int) {
        if let index = widgets.firstIndex(where: { $0.id == id }) { moveWidget(at: index, by: delta) }
    }

    func updateNote(id: UUID, text: String) {
        guard let index = widgets.firstIndex(where: { $0.id == id }), widgets[index].text != text else { return }
        widgets[index].text = text
    }

    // MARK: - Raf (odaklanan kutunun kısayolları)

    var shelfItems: [ShelfItem] { items(for: currentTile) }

    var focusedShelfIndex: Int {
        guard area == .shelf else { return -1 }
        return min(shelfIndex, shelfItems.count - 1)
    }

    /// Arka planda açık bir web servisi için rafın başına "Devam Et" ve "Kapat" eklenir.
    private func items(for tile: Tile) -> [ShelfItem] {
        guard tile.webURL != nil, openWebTiles.contains(tile.id) else { return baseItems(for: tile) }
        let p = tile.id + "."
        return [
            ShelfItem(id: p + "resume", title: "Devam Et", subtitle: "Kaldığın yerden",
                      style: .action(symbol: "play.fill"), command: .resumeWeb(tile.id)),
            ShelfItem(id: p + "close", title: "Kapat", subtitle: "Arka planda açık",
                      style: .action(symbol: "xmark"), command: .closeWeb(tile.id)),
        ] + baseItems(for: tile)
    }

    private func baseItems(for tile: Tile) -> [ShelfItem] {
        let p = tile.id + "."
        func web(_ id: String, _ title: String, _ symbol: String, _ url: String) -> ShelfItem {
            ShelfItem(id: p + id, title: title, style: .action(symbol: symbol), command: .web(URL(string: url)!, tileID: tile.id))
        }
        func action(_ id: String, _ title: String, _ symbol: String, _ command: HubCommand, subtitle: String? = nil) -> ShelfItem {
            ShelfItem(id: p + id, title: title, subtitle: subtitle, style: .action(symbol: symbol), command: command)
        }
        let openApp = HubCommand.launchApp(tile.bundleIDs, fallback: tile.fallbackURL)

        switch tile.id {
        case "steam":
            var items = [action("bigpicture", "Big Picture", "tv.and.mediabox.fill", .external(URL(string: "steam://open/bigpicture")!), subtitle: "TV modu")]
            items += steam.games.prefix(12).map { game in
                ShelfItem(id: p + "game-" + game.id, title: game.name, subtitle: Fmt.relative(game.lastPlayed),
                          style: .poster(game), command: .external(game.runURL))
            }
            items += [
                action("library", "Kütüphane", "books.vertical.fill", .external(URL(string: "steam://open/games")!)),
                action("store", "Mağaza", "bag.fill", .external(URL(string: "steam://store")!)),
                action("friends", "Arkadaşlar", "person.2.fill", .external(URL(string: "steam://open/friends")!)),
            ]
            return items

        case "netflix":
            return [
                web("home", "Ana Sayfa", "house.fill", "https://www.netflix.com/browse"),
                web("mylist", "Listem", "plus.rectangle.on.rectangle", "https://www.netflix.com/browse/my-list"),
                web("series", "Diziler", "tv.fill", "https://www.netflix.com/browse/genre/83"),
                web("movies", "Filmler", "film.fill", "https://www.netflix.com/browse/genre/34399"),
                web("new", "Yeni ve Popüler", "flame.fill", "https://www.netflix.com/latest"),
                web("search", "Ara", "magnifyingglass", "https://www.netflix.com/search"),
            ]

        case "appletv":
            return [
                action("open", "Apple TV'yi Aç", "play.tv.fill", openApp, subtitle: "Uygulama"),
                web("web", "Web'de Aç", "globe", "https://tv.apple.com"),
            ]

        case "prime":
            return [
                action("open", "Prime Video'yu Aç", "play.rectangle.fill", openApp, subtitle: "Uygulama"),
                web("web", "Web'de Aç", "globe", "https://www.primevideo.com"),
            ]

        case "tvplus":
            return [
                web("home", "Ana Sayfa", "house.fill", "https://tvplus.com.tr"),
                web("live", "Canlı TV", "antenna.radiowaves.left.and.right", "https://tvplus.com.tr/canli-tv"),
                web("series", "Diziler", "tv.fill", "https://tvplus.com.tr/dizi-izle"),
                web("movies", "Filmler", "film.fill", "https://tvplus.com.tr/film-izle"),
                web("sport", "Spor", "sportscourt.fill", "https://tvplus.com.tr/spor"),
                web("hbo", "HBO", "play.rectangle.on.rectangle.fill", "https://tvplus.com.tr/hbo"),
                web("docs", "Belgesel", "globe.europe.africa.fill", "https://tvplus.com.tr/belgesel-izle"),
            ]

        case "youtube":
            return [
                web("home", "Ana Sayfa", "house.fill", "https://www.youtube.com"),
                web("subs", "Abonelikler", "play.square.stack.fill", "https://www.youtube.com/feed/subscriptions"),
                web("later", "Daha Sonra İzle", "clock.fill", "https://www.youtube.com/playlist?list=WL"),
                web("history", "Geçmiş", "clock.arrow.circlepath", "https://www.youtube.com/feed/history"),
                web("music", "YouTube Music", "music.note", "https://music.youtube.com"),
            ]

        case "twitch":
            return [
                web("home", "Ana Sayfa", "house.fill", "https://www.twitch.tv"),
                web("following", "Takip Edilenler", "heart.fill", "https://www.twitch.tv/directory/following"),
                web("browse", "Göz At", "square.grid.2x2.fill", "https://www.twitch.tv/directory"),
            ]

        case "spotify":
            let open = action("open", "Spotify'ı Aç", "arrow.up.forward.app.fill", openApp)
            if spotify.hasTrack {
                return [
                    ShelfItem(id: p + "now", title: spotify.track ?? "", subtitle: spotify.artist, style: .nowPlaying, command: .spotify(.playPause)),
                    action("prev", "Önceki", "backward.fill", .spotify(.previous)),
                    action("toggle", spotify.isPlaying ? "Duraklat" : "Oynat", spotify.isPlaying ? "pause.fill" : "play.fill", .spotify(.playPause)),
                    action("next", "Sonraki", "forward.fill", .spotify(.next)),
                    open,
                ]
            }
            if spotify.isRunning {
                return [action("toggle", "Oynat", "play.fill", .spotify(.playPause)), open]
            }
            return [open]

        case "reddit":
            return [
                web("home", "Ana Sayfa", "house.fill", "https://www.reddit.com"),
                web("popular", "Popüler", "flame.fill", "https://www.reddit.com/r/popular"),
                web("all", "Tümü", "globe", "https://www.reddit.com/r/all"),
            ]

        default:
            return []
        }
    }

    var heroSubtitle: String {
        let tile = currentTile
        switch tile.id {
        case "steam":
            return steam.games.isEmpty ? "Yüklü oyun yok · Big Picture ile TV modunda açabilirsin" : "\(steam.games.count) yüklü oyun"
        case "spotify":
            if spotify.hasTrack {
                return (spotify.isPlaying ? "Çalıyor" : "Duraklatıldı") + " · \(spotify.track ?? "") — \(spotify.artist ?? "")"
            }
            return spotify.isRunning ? "Spotify açık · şu an bir şey çalmıyor" : tile.tagline
        default:
            if tile.webURL != nil {
                if openWebTiles.contains(tile.id) { return tile.tagline + " · arka planda açık, kaldığın yerden devam edebilirsin" }
                return tile.tagline + (settings.webMode == .inApp ? " · Hub içinde açılır" : " · Tarayıcıda açılır")
            }
            return tile.tagline
        }
    }

    var heroImageURL: URL? {
        switch currentTile.id {
        case "spotify":
            return spotify.hasTrack ? spotify.artworkURL : nil
        case "steam":
            let items = shelfItems
            if area == .shelf, items.indices.contains(shelfIndex), case let .poster(game) = items[shelfIndex].style {
                return game.heroURL
            }
            return steam.games.first?.heroURL
        default:
            return nil
        }
    }

    var hint: String {
        if overlay == .picker { return "← → ↑ ↓  seç     ⏎  ekle     esc  kapat" }
        if overlay == .settings { return "esc  kapat" }
        switch area {
        case .apps: return "← →  gez     ↑  kısayollar     ↓  widget'lar     ⏎  aç     ⌃⌥H  her yerden Hub'a dön"
        case .shelf: return "← →  gez     ⏎  aç     ↓  uygulamalar"
        case .widgets:
            return widgetIndex >= widgets.count
                ? "⏎  widget ekle     ↑  uygulamalar"
                : "⏎  aç     ⌫  kaldır     ⌥← ⌥→  taşı     ↑  uygulamalar"
        }
    }

    // MARK: - Ekran görüntüsü testi için

    func applyDebugState(_ text: String) {
        for pair in text.split(separator: ";") {
            let kv = pair.split(separator: "=").map(String.init)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "app": if let i = Int(kv[1]) { appIndex = min(max(0, i), tiles.count - 1) }
            case "area": area = kv[1] == "shelf" ? .shelf : kv[1] == "widgets" ? .widgets : .apps
            case "shelf": shelfIndex = Int(kv[1]) ?? 0
            case "widget": widgetIndex = Int(kv[1]) ?? 0
            case "overlay": overlay = kv[1] == "picker" ? .picker : kv[1] == "settings" ? .settings : nil
            case "web": if let tile = Tile.all.first(where: { $0.id == kv[1] }) { openWeb(url: nil, tile: tile) }
            case "hide": settings.hiddenTiles = Set(kv[1].split(separator: ",").map(String.init))
            case "widgetAdd": if let kind = WidgetKind(rawValue: kv[1]) { widgets.append(WidgetInstance(kind: kind)) }
            case "open": openWebTiles.insert(kv[1])
            case "click":
                for index in kv[1].split(separator: ",").compactMap({ Int($0) }) { clickApp(index) }
                print("TEST tıklama sonrası: seçili=\(currentTile.id) alan=\(area) web açık=\(webSession != nil)")
            case "keys": for ch in kv[1] { handle(ch == "R" ? .right : ch == "L" ? .left : ch == "U" ? .up : .down) }
            case "edge":
                let parts = kv[1].split(separator: ":")
                let row: HomeRow = parts.first == "shelf" ? .shelf : parts.first == "widgets" ? .widgets : .apps
                edgeScroll = EdgeScroll(row: row, direction: Int(parts.last ?? "1") ?? 1)
            case "spotifyArt":
                spotify.isRunning = true
                spotify.isPlaying = true
                spotify.track = "Test şarkısı"
                spotify.artist = "Test sanatçı"
                spotify.duration = 200
                spotify.artworkURL = URL(fileURLWithPath: kv[1])
            default: break
            }
        }
    }
}

enum Fmt {
    static let tr = Locale(identifier: "tr_TR")

    static let time: DateFormatter = make("HH:mm")
    static let seconds: DateFormatter = make("ss")
    static let longDate: DateFormatter = make("d MMMM EEEE")
    static let weekday: DateFormatter = make("EEEE")
    static let shortDay: DateFormatter = make("d MMM")

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = tr
        f.dateFormat = format
        return f
    }

    static func relative(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = RelativeDateTimeFormatter()
        f.locale = tr
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: Date())
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func greeting(_ date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Günaydın"
        case 12..<18: "İyi günler"
        case 18..<23: "İyi akşamlar"
        default: "İyi geceler"
        }
    }

    static func eventTime(_ item: CalendarItem) -> String {
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(item.start) { day = "Bugün" }
        else if cal.isDateInTomorrow(item.start) { day = "Yarın" }
        else { day = weekday.string(from: item.start).capitalized(with: tr) }
        return item.isAllDay ? "\(day) · tüm gün" : "\(day) \(time.string(from: item.start))"
    }
}
