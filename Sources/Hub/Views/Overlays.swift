import SwiftUI

// MARK: - Widget seçici

struct WidgetPickerView: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .onTapGesture { store.overlay = nil }

            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Widget Ekle").font(.system(size: 34, weight: .bold))
                    Text("Ana ekranın alt satırına eklenir. Sonra ⌫ ile kaldırabilir, ⌥← ⌥→ ile taşıyabilirsin.")
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.65))
                }
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(220), spacing: 20), count: 4), spacing: 20) {
                    ForEach(Array(WidgetKind.allCases.enumerated()), id: \.element) { index, kind in
                        let focused = index == store.pickerIndex
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 26, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                Spacer()
                                if kind.isWide {
                                    Text("GENİŞ")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(.white.opacity(0.15), in: .capsule)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(kind.title).font(.system(size: 17, weight: .bold))
                            Text(kind.summary)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(2)
                        }
                        .padding(18)
                        .frame(width: 220, height: 150, alignment: .leading)
                        .glassCard(cornerRadius: 22, tint: focused ? .white.opacity(0.18) : nil)
                        .focusLift(focused, scale: 1.06)
                        .contentShape(.rect)
                        .pointerStyle(.link)
                        .onTapGesture { store.addWidget(kind) }
                    }
                }
                .frame(width: 4 * 220 + 3 * 20)
                Text(store.hint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(40)
            .fixedSize()
            .panelBackground(cornerRadius: 38)
        }
    }
}

// MARK: - Ayarlar

struct SettingsView: View {
    @Environment(HubStore.self) private var store
    @State private var city = ""

    var body: some View {
        @Bindable var store = store
        ZStack {
            Color.black.opacity(0.62)
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Ayarlar").font(.system(size: 34, weight: .bold))
                    Spacer()
                    Button("Kapat") { close() }
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.large)
                }

                Form {
                    Section {
                        ForEach(Tile.all) { tile in
                            let shown = !store.settings.hiddenTiles.contains(tile.id)
                            Toggle(isOn: Binding(
                                get: { !store.settings.hiddenTiles.contains(tile.id) },
                                set: { show in
                                    if show { store.settings.hiddenTiles.remove(tile.id) }
                                    else { store.settings.hiddenTiles.insert(tile.id) }
                                }
                            )) {
                                HStack(spacing: 12) {
                                    TileArtwork(tile: tile, size: CGSize(width: 56, height: 32))
                                        .clipShape(.rect(cornerRadius: 7, style: .continuous))
                                        .opacity(shown ? 1 : 0.4)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tile.name)
                                        Text(tile.tagline).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.switch)
                            // Son görünen uygulama kapatılamaz.
                            .disabled(shown && store.tiles.count == 1)
                        }
                    } header: {
                        Text("Ana ekrandaki uygulamalar")
                    } footer: {
                        Text("Kapattığın uygulama ana satırdan kalkar, istediğin zaman geri açabilirsin. Widget'lar etkilenmez.")
                    }

                    Section("Hava durumu") {
                        TextField("Şehir", text: $city)
                            .onSubmit { store.settings.city = city }
                        if let name = store.weather.cityName {
                            LabeledContent("Bulunan konum", value: name)
                        }
                    }

                    Section("Web servisleri (Netflix, TV+, YouTube, Twitch, Reddit)") {
                        Picker("Açılış şekli", selection: $store.settings.webMode) {
                            Text("Hub içinde, tam ekran").tag(WebMode.inApp)
                            Text("Varsayılan tarayıcıda").tag(WebMode.browser)
                        }
                        Toggle("Ana ekrana dönünce arka planda açık tut", isOn: $store.settings.keepWebOpen)
                            .toggleStyle(.switch)
                        Text("Açıksa ⌘W ile döndüğünde video durur, sonra kaldığın yerden devam edersin. Tamamen kapatmak için ⇧⌘W ya da üstteki Kapat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Toggle("Başka uygulamaya geçince Hub'ı arkada gösterme", isOn: $store.settings.hideWhenInactive)
                            .toggleStyle(.switch)
                        Toggle("Hub öndeyken Dock'u tamamen gizle", isOn: $store.settings.hideDock)
                            .toggleStyle(.switch)
                    } header: {
                        Text("Görünüm")
                    } footer: {
                        Text("Hub saklıyken geri dönmek için ⌃⌥H, ⌘Tab ya da Dock'taki Hub simgesi. Dock gizleme kapalıysa Dock, fare ekranın altına gelince açılır.")
                    }

                    Section("Kısayollar") {
                        LabeledContent("Her yerden Hub'a dön", value: "⌃⌥H")
                        LabeledContent("Gezinme", value: "Ok tuşları · ⏎ · esc · kumanda")
                        LabeledContent("Web'den ana ekrana", value: "⌘W")
                        LabeledContent("Web servisini kapat", value: "⇧⌘W")
                        LabeledContent("Widget ekle", value: "⌘N")
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
            .padding(32)
            .frame(width: 640, height: min(store.screenSize.height - 120, 900))
            .panelBackground(cornerRadius: 34)
        }
        .onAppear { city = store.settings.city }
        .onDisappear { commitCity() }
    }

    private func commitCity() {
        let trimmed = city.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != store.settings.city { store.settings.city = trimmed }
    }

    private func close() {
        commitCity()
        store.overlay = nil
    }
}
