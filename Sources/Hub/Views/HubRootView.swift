import SwiftUI

struct HubRootView: View {
    @Environment(HubStore.self) private var store

    var body: some View {
        ZStack {
            LiveBackground(
                tile: store.currentTile,
                imageURL: store.heroImageURL,
                paused: store.webSession != nil || !store.isActive
            )

            HomeView()
                .opacity(store.webSession == nil ? 1 : 0)
                .blur(radius: store.overlay == nil ? 0 : 10)
                .allowsHitTesting(store.webSession == nil && store.overlay == nil)

            if let session = store.webSession {
                WebPlayerView(session: session)
                    .transition(.opacity)
            }

            switch store.overlay {
            case .picker: WidgetPickerView().transition(.opacity)
            case .settings: SettingsView().transition(.opacity)
            case nil: EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.overlay)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .foregroundStyle(.white)
    }
}

/// Odaklanan uygulamanın renklerine bürünen, yavaşça akan arka plan.
struct LiveBackground: View {
    let tile: Tile
    let imageURL: URL?
    let paused: Bool

    var body: some View {
        ZStack {
            Color.black

            ZStack {
                MeshLayer(accent: tile.accent, base: tile.background.last ?? .black, paused: paused)
                    .id(tile.id)
                    .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.9), value: tile.id)

            if let imageURL {
                // Color.clear ekran boyutunu alır; görsel onun içine sığdırılır.
                // (Doğrudan scaledToFill kare kapağı ekran genişliğine büyütüp tüm düzeni kaydırıyordu.)
                Color.clear
                    .overlay {
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                                    .blur(radius: 60)
                                    .saturation(1.25)
                                    .opacity(0.5)
                            }
                        }
                    }
                    .clipped()
                    .id(imageURL)
                    .transition(.opacity)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.05), location: 0),
                    .init(color: .black.opacity(0.25), location: 0.45),
                    .init(color: .black.opacity(0.7), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .animation(.easeInOut(duration: 0.8), value: imageURL)
        .clipped()
    }
}

private struct MeshLayer: View {
    let accent: Color
    let base: Color
    let paused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000))
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + 0.18 * sin(t * 0.21), 0], [1, 0],
                    [0, 0.5 + 0.2 * cos(t * 0.17)], [0.5 + 0.16 * sin(t * 0.27), 0.45 + 0.14 * cos(t * 0.23)], [1, 0.5 + 0.2 * sin(t * 0.19)],
                    [0, 1], [0.5 + 0.2 * cos(t * 0.15), 1], [1, 1],
                ],
                colors: [
                    accent.mix(with: .black, by: 0.3), base.mix(with: .black, by: 0.45), .black,
                    base.mix(with: .black, by: 0.35), accent.mix(with: .black, by: 0.6), accent.mix(with: .black, by: 0.72),
                    .black, base.mix(with: .black, by: 0.7), accent.mix(with: .black, by: 0.55),
                ]
            )
        }
    }
}
