import SwiftUI

struct WidgetCard: View {
    let widget: WidgetInstance
    let focused: Bool

    var body: some View {
        content
            .padding(18)
            .frame(width: widget.kind.isWide ? WidgetMetrics.wide : WidgetMetrics.unit,
                   height: WidgetMetrics.height, alignment: .topLeading)
            .glassCard(cornerRadius: 26, tint: focused ? .white.opacity(0.12) : nil)
            .focusLift(focused, scale: 1.05, cornerRadius: 26)
    }

    @ViewBuilder
    private var content: some View {
        switch widget.kind {
        case .clock: ClockWidget()
        case .weather: WeatherWidget()
        case .spotify: SpotifyWidget()
        case .steam: SteamWidget()
        case .battery: BatteryWidget()
        case .memory: MemoryWidget()
        case .note: NoteWidget(widget: widget)
        case .calendar: CalendarWidget()
        }
    }
}

/// Widget içinde ikon + başlık + açıklama durumu.
private struct WidgetStatus: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.8))
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
        }
    }
}

// MARK: - Saat

private struct ClockWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                WidgetHeader(kind: .clock)
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Fmt.time.string(from: context.date))
                        .font(.system(size: 50, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(Fmt.seconds.string(from: context.date))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text(Fmt.longDate.string(from: context.date))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Hava durumu

private struct WeatherWidget: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        let weather = store.weather
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(kind: .weather)
            if let temp = weather.temperature {
                Spacer(minLength: 0)
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: weather.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 38))
                    Text("\(Int(temp.rounded()))°")
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                }
                Text(weather.summary).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(weather.cityName ?? store.settings.city).lineLimit(1)
                    if let high = weather.high, let low = weather.low {
                        Text("↑\(Int(high.rounded()))° ↓\(Int(low.rounded()))°").fixedSize()
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            } else {
                WidgetStatus(symbol: "cloud.sun", title: weather.failed ? "Alınamadı" : "Yükleniyor…",
                             detail: weather.failed ? "Şehri Ayarlar'dan kontrol et" : store.settings.city)
            }
        }
    }
}

// MARK: - Spotify

private struct SpotifyWidget: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        let spotify = store.spotify
        HStack(spacing: 16) {
            RemoteImage(primary: spotify.artworkURL, placeholderSymbol: "music.note")
                .frame(width: 132, height: 132)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(kind: .spotify)
                Spacer(minLength: 0)
                if spotify.hasTrack {
                    HStack(spacing: 6) {
                        Image(systemName: spotify.isPlaying ? "waveform" : "pause.fill")
                            .symbolEffect(.variableColor.iterative, isActive: spotify.isPlaying)
                            .foregroundStyle(Color(hex: 0x1ED760))
                        Text(spotify.track ?? "").lineLimit(1)
                    }
                    .font(.system(size: 17, weight: .bold))
                    Text(spotify.artist ?? "")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                    PlaybackProgress(spotify: spotify).padding(.top, 6)
                } else {
                    Text(spotify.isRunning ? "Şu an bir şey çalmıyor" : "Spotify kapalı")
                        .font(.system(size: 17, weight: .semibold))
                    Text(spotify.isRunning ? "⏎ ile oynat" : "⏎ ile aç")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Steam

private struct SteamWidget: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        let games = store.steam.games
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(kind: .steam, trailing: games.isEmpty ? nil : "\(games.count) oyun")
            if games.isEmpty {
                WidgetStatus(symbol: "gamecontroller", title: "Yüklü oyun yok", detail: "⏎ ile Steam kısayollarına git")
            } else {
                HStack(spacing: 10) {
                    ForEach(games.prefix(5)) { game in
                        RemoteImage(primary: game.posterURL, fallback: game.headerURL, placeholderSymbol: "gamecontroller.fill")
                            .frame(width: 64, height: 96)
                            .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }
}

// MARK: - Pil

private struct BatteryWidget: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        let system = store.system
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(kind: .battery)
            if let level = system.batteryLevel {
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.15), lineWidth: 9)
                        Circle()
                            .trim(from: 0, to: CGFloat(level) / 100)
                            .stroke(color(level), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        if system.isCharging {
                            Image(systemName: "bolt.fill").font(.system(size: 20)).foregroundStyle(.yellow)
                        }
                    }
                    .frame(width: 70, height: 70)
                    Text("%\(level)")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                }
                Text(status(system))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            } else {
                WidgetStatus(symbol: "powerplug.fill", title: "Pil yok", detail: "Prize bağlı")
            }
        }
    }

    private func color(_ level: Int) -> Color {
        level <= 20 ? .red : level <= 40 ? .orange : .green
    }

    private func status(_ system: SystemService) -> String {
        if system.isCharging { return "Şarj oluyor" }
        if system.onAC { return "Prize bağlı" }
        if let minutes = system.minutesLeft { return "~\(minutes / 60) sa \(minutes % 60) dk kaldı" }
        return "Pilde"
    }
}

// MARK: - Hub belleği

private struct MemoryWidget: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        let memory = store.hubMemory
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(kind: .memory)
            if memory.updated {
                Spacer(minLength: 0)
                Text(HubMemoryService.format(memory.total))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(memory.slices) { slice in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color(slice))
                                .frame(width: max(3, geo.size.width * CGFloat(slice.bytes) / CGFloat(max(memory.total, 1)) - 2))
                        }
                    }
                    .animation(.easeInOut(duration: 0.5), value: memory.slices)
                }
                .frame(height: 8)
                .padding(.bottom, 2)
                ForEach(legend(memory), id: \.name) { line in
                    HStack(spacing: 5) {
                        Circle().fill(line.color).frame(width: 7, height: 7)
                        Text(line.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(HubMemoryService.format(line.bytes))
                            .foregroundStyle(.white.opacity(0.55))
                            .monospacedDigit()
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            } else {
                WidgetStatus(symbol: "memorychip", title: "Ölçülüyor…", detail: "Hub ve web sayfaları")
            }
        }
    }

    private struct Line { let name: String; let bytes: UInt64; let color: Color }

    /// Küçük kutuya iki satır: Hub'ın kendisi ve web sayfaları (tek servis açıksa onun adıyla).
    private func legend(_ memory: HubMemoryService) -> [Line] {
        var app: UInt64 = 0, web: UInt64 = 0
        var tiles: [String] = []
        for slice in memory.slices {
            switch slice.kind {
            case .app: app += slice.bytes
            case .web(let tileID): web += slice.bytes; tiles.append(tileID)
            case .shared: web += slice.bytes
            }
        }
        var lines = [Line(name: "Hub", bytes: app, color: .white.opacity(0.85))]
        if web > 0 {
            if tiles.count == 1, let tile = Tile.all.first(where: { $0.id == tiles[0] }) {
                lines.append(Line(name: tile.name, bytes: web, color: tile.accent))
            } else {
                lines.append(Line(name: "Web sayfaları", bytes: web, color: .white.opacity(0.3)))
            }
        }
        return lines
    }

    private func color(_ slice: HubMemoryService.Slice) -> Color {
        switch slice.kind {
        case .app: .white.opacity(0.85)
        case .web(let tileID): Tile.all.first { $0.id == tileID }?.accent ?? .gray
        case .shared: .white.opacity(0.3)
        }
    }
}

// MARK: - Not

private struct NoteWidget: View {
    @Environment(HubStore.self) private var store
    let widget: WidgetInstance
    @State private var text = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(kind: .note, trailing: editing ? "esc ile bitir" : nil)
            TextEditor(text: $text)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .focused($editing)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty && !editing {
                        Text("Bir not yaz…  (⏎)")
                            .font(.system(size: 15))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .onAppear { text = widget.text }
        .onChange(of: text) { _, value in store.updateNote(id: widget.id, text: value) }
        .onChange(of: store.editingNoteID) { _, id in editing = id == widget.id }
        .onChange(of: editing) { _, isEditing in
            if !isEditing, store.editingNoteID == widget.id { store.editingNoteID = nil }
        }
    }
}

// MARK: - Takvim

private struct CalendarWidget: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        let calendar = store.calendar
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(kind: .calendar)
            switch calendar.access {
            case .granted:
                if calendar.items.isEmpty {
                    WidgetStatus(symbol: "calendar.badge.checkmark", title: "Etkinlik yok", detail: "Önümüzdeki 3 gün boş")
                } else {
                    ForEach(calendar.items.prefix(3)) { item in
                        HStack(spacing: 10) {
                            Capsule().fill(item.color).frame(width: 4, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                Text(Fmt.eventTime(item)).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                }
            case .denied:
                WidgetStatus(symbol: "calendar.badge.exclamationmark", title: "Takvim izni yok",
                             detail: "Sistem Ayarları › Gizlilik › Takvimler")
            case .unknown:
                WidgetStatus(symbol: "calendar", title: "İzin bekleniyor…", detail: "macOS takvim erişimi soracak")
            }
        }
    }
}
