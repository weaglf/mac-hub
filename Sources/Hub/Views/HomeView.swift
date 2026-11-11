import SwiftUI

struct HomeView: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar()
                .padding(.top, max(store.safeTop, 12) + 16)
                .padding(.horizontal, 64)

            ShelfView()
                .frame(maxHeight: .infinity, alignment: .bottom)

            AppRow()

            WidgetRow()

            Text(store.hint)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
                .contentTransition(.opacity)
        }
    }
}

// MARK: - Üst çubuk

struct TopBar: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.greeting(context.date))
                        .font(.system(size: 28, weight: .bold))
                    Text(Fmt.longDate.string(from: context.date))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    // Günün sözü: gece yarısı değişir. Soldaki çizgi seçili uygulamanın rengini alır.
                    Text(DailyQuote.text(for: context.date))
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .padding(.leading, 13)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(store.currentTile.accent)
                                .frame(width: 3)
                                .animation(.easeInOut(duration: 0.6), value: store.currentTile.id)
                        }
                        .frame(maxWidth: store.screenSize.width * 0.45, alignment: .leading)
                        .padding(.top, 12)
                        .contentTransition(.opacity)
                }
                Spacer()
                HStack(spacing: 26) {
                    if let temp = store.weather.temperature {
                        HStack(spacing: 8) {
                            Image(systemName: store.weather.symbol).symbolRenderingMode(.multicolor)
                            Text("\(Int(temp.rounded()))°")
                        }
                        .font(.system(size: 22, weight: .semibold))
                    }
                    if let level = store.system.batteryLevel {
                        HStack(spacing: 6) {
                            Image(systemName: batterySymbol(level))
                            Text("%\(level)")
                        }
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                    }
                    Text(Fmt.time.string(from: context.date))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Button {
                        store.toggleSettings()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 42, height: 42)
                            .glassEffect(.regular, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .focusEffectDisabled()
                    .help("Ayarlar (⌘,)")
                }
            }
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        if store.system.isCharging { return "battery.100percent.bolt" }
        switch level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

// MARK: - Raf (odaklanan uygulamanın içeriği)

struct ShelfView: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        let tile = store.currentTile
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                HeroArt()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 90)
                    .padding(.top, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text(tile.name)
                        .font(.system(size: 54, weight: .bold))
                    Text(store.heroSubtitle)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(.horizontal, 64)
                .id(tile.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 30)), removal: .opacity))
            }

            ShelfRow(items: store.shelfItems, focusIndex: store.focusedShelfIndex, accent: tile.accent)
                .id("row-" + tile.id)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.28), value: tile.id)
    }
}

/// Rafın sağ üstündeki büyük görsel: çalan albüm, seçili oyun ya da markanın logosu.
private struct HeroArt: View {
    @Environment(HubStore.self) private var store
    @State private var floating = false

    var body: some View {
        GeometryReader { geo in
            let h = min(geo.size.height, 300)
            Group {
                if h >= 90 {
                    art(h)
                        .id(artID)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
        }
        .offset(y: floating ? -5 : 5)
        .animation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true), value: floating)
        .animation(.easeOut(duration: 0.35), value: artID)
        .onAppear { floating = true }
        .allowsHitTesting(false)
    }

    private var artID: String {
        store.currentTile.id + (store.heroImageURL?.absoluteString ?? "")
    }

    @ViewBuilder
    private func art(_ h: CGFloat) -> some View {
        let tile = store.currentTile
        if tile.id == "spotify", store.spotify.hasTrack {
            RemoteImage(primary: store.spotify.artworkURL, placeholderSymbol: "music.note")
                .frame(width: h, height: h)
                .clipShape(.rect(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
        } else if tile.id == "steam", let url = store.heroImageURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                        .frame(maxHeight: h)
                        .clipShape(.rect(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
                }
            }
        } else {
            TileLogo(tile: tile, height: h * 0.85)
                .shadow(color: tile.accent.opacity(0.45), radius: 50)
                .opacity(0.92)
        }
    }
}

private struct ShelfRow: View {
    @Environment(HubStore.self) private var store
    let items: [ShelfItem]
    let focusIndex: Int
    let accent: Color

    var body: some View {
        EdgeScrollRow(row: .shelf, targetID: items.indices.contains(focusIndex) ? items[focusIndex].id : nil) {
            HStack(alignment: .bottom, spacing: 20) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ShelfCard(item: item, focused: index == focusIndex, accent: accent)
                        .scrollTarget(item.id)
                        .contentShape(.rect)
                        .pointerStyle(.link)
                        .onTapGesture { store.clickShelf(index) }
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 22)
        }
    }
}

// MARK: - Uygulama satırı

struct AppRow: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        let size = store.tileSize
        EdgeScrollRow(row: .apps, targetID: store.currentTile.id) {
            HStack(spacing: 28) {
                ForEach(Array(store.tiles.enumerated()), id: \.element.id) { index, tile in
                    TileView(
                        tile: tile, size: size,
                        focused: store.area == .apps && store.appIndex == index,
                        selected: store.appIndex == index,
                        isOpen: store.openWebTiles.contains(tile.id)
                    )
                    .scrollTarget(tile.id)
                    .contentShape(.rect)
                    .pointerStyle(.link)
                    .onTapGesture { store.clickApp(index) }
                }
            }
            .padding(.horizontal, 64)
            .padding(.top, 20)
            .padding(.bottom, 6)
        }
        .frame(height: size.height + 20 + 6 + 40)
    }
}

// MARK: - Widget satırı

enum WidgetMetrics {
    static let unit: CGFloat = 196
    static let wide: CGFloat = 412
    static let height: CGFloat = 168
}

struct WidgetRow: View {
    @Environment(HubStore.self) private var store

    private var targetID: String {
        store.widgets.indices.contains(store.widgetIndex) ? store.widgets[store.widgetIndex].id.uuidString : "add"
    }

    var body: some View {
        EdgeScrollRow(row: .widgets, targetID: targetID) {
            HStack(spacing: 20) {
                ForEach(Array(store.widgets.enumerated()), id: \.element.id) { index, widget in
                    WidgetCard(widget: widget, focused: store.area == .widgets && store.widgetIndex == index)
                        .scrollTarget(widget.id.uuidString)
                        .contentShape(.rect)
                        .pointerStyle(.link)
                        .onTapGesture { store.clickWidget(index) }
                        .contextMenu {
                            Button("Sola Taşı", systemImage: "arrow.left") { store.moveWidget(id: widget.id, by: -1) }
                            Button("Sağa Taşı", systemImage: "arrow.right") { store.moveWidget(id: widget.id, by: 1) }
                            Divider()
                            Button("Kaldır", systemImage: "trash", role: .destructive) { store.removeWidget(id: widget.id) }
                        }
                }
                AddWidgetCard(focused: store.area == .widgets && store.widgetIndex >= store.widgets.count)
                    .scrollTarget("add")
                    .contentShape(.rect)
                    .pointerStyle(.link)
                    .onTapGesture { store.openPicker() }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 18)
        }
        .frame(height: WidgetMetrics.height + 36)
    }
}

private struct AddWidgetCard: View {
    let focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .semibold))
            Text("Widget Ekle")
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(focused ? 1 : 0.6))
        .frame(width: WidgetMetrics.unit, height: WidgetMetrics.height)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.28), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
        }
        .focusLift(focused, scale: 1.05, cornerRadius: 26)
    }
}
