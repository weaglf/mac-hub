import SwiftUI

struct ShelfCard: View {
    @Environment(HubStore.self) private var store
    let item: ShelfItem
    let focused: Bool
    let accent: Color

    var body: some View {
        switch item.style {
        case .action(let symbol): action(symbol)
        case .message(let symbol): message(symbol)
        case .poster(let game): poster(game)
        case .nowPlaying: nowPlaying
        }
    }

    private var tint: Color? { focused ? accent.opacity(0.4) : nil }

    private func action(_ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Spacer(minLength: 0)
            Text(item.title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(18)
        .frame(width: 176, height: 124, alignment: .leading)
        .glassCard(cornerRadius: 22, tint: tint)
        .focusLift(focused)
    }

    private func message(_ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 18, weight: .bold))
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 124, alignment: .topLeading)
        .glassCard(cornerRadius: 22, tint: tint)
        .focusLift(focused, scale: 1.05)
    }

    private func poster(_ game: SteamGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteImage(primary: game.posterURL, fallback: game.headerURL, placeholderSymbol: "gamecontroller.fill")
                .frame(width: 128, height: 192)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .focusLift(focused, scale: 1.1, cornerRadius: 16)
        }
        .overlay(alignment: .bottom) {
            if focused {
                VStack(spacing: 2) {
                    Text(game.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .frame(width: 170)
                .offset(y: 46)
            }
        }
    }

    private var nowPlaying: some View {
        let spotify = store.spotify
        return HStack(spacing: 18) {
            RemoteImage(primary: spotify.artworkURL, placeholderSymbol: "music.note")
                .frame(width: 124, height: 124)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: spotify.isPlaying ? "waveform" : "pause.fill")
                        .symbolEffect(.variableColor.iterative, isActive: spotify.isPlaying)
                    Text(spotify.isPlaying ? "ŞU AN ÇALIYOR" : "DURAKLATILDI")
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: 0x1ED760))
                Text(spotify.track ?? "")
                    .font(.system(size: 21, weight: .bold))
                    .lineLimit(1)
                Text(spotify.artist ?? "")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 0)
                PlaybackProgress(spotify: spotify)
            }
        }
        .padding(14)
        .frame(width: 470, height: 152)
        .glassCard(cornerRadius: 24, tint: tint)
        .focusLift(focused, scale: 1.05, cornerRadius: 24)
    }

}
