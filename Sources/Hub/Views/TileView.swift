import SwiftUI

struct TileView: View {
    let tile: Tile
    let size: CGSize
    let focused: Bool
    let selected: Bool
    /// Web servisi arka planda açık mı (Dock'taki gibi nokta).
    var isOpen = false

    var body: some View {
        VStack(spacing: 14) {
            TileArtwork(tile: tile, size: size)
                .overlay {
                    // TV'lerdeki parlama efekti
                    LinearGradient(
                        colors: [.white.opacity(focused ? 0.22 : 0.06), .clear],
                        startPoint: .topLeading, endPoint: .center
                    )
                }
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
                .focusLift(focused, scale: 1.1, cornerRadius: 22)

            Text(tile.name)
                .font(.system(size: 17, weight: .semibold))
                .opacity(focused ? 1 : selected ? 0.55 : 0)
                .offset(y: focused ? 6 : 0)
                .animation(.easeOut(duration: 0.2), value: focused)
                .overlay(alignment: .top) {
                    if isOpen {
                        Circle()
                            .fill(.white.opacity(0.85))
                            .frame(width: 6, height: 6)
                            .offset(y: focused ? -4 : -8)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: isOpen)
        }
    }
}

struct TileArtwork: View {
    let tile: Tile
    let size: CGSize

    var body: some View {
        ZStack {
            LinearGradient(colors: tile.background, startPoint: .topLeading, endPoint: .bottomTrailing)
            TileLogo(tile: tile, height: size.height)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Markanın logosu; `height` kutu yüksekliğine göre ölçeklenir.
struct TileLogo: View {
    let tile: Tile
    let height: CGFloat

    var body: some View { logo(height) }

    @ViewBuilder
    private func logo(_ h: CGFloat) -> some View {
        switch tile.logo {
        case .appIcon(let fallback):
            if let icon = Launcher.icon(tile.bundleIDs) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: h * 0.68, height: h * 0.68)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            } else {
                Text(fallback).font(.system(size: h * 0.22, weight: .heavy))
            }

        case .netflix:
            Text("NETFLIX")
                .font(.system(size: h * 0.28, weight: .black).width(.condensed))
                .kerning(h * 0.012)
                .foregroundStyle(Color(hex: 0xE50914))
                .shadow(color: Color(hex: 0xE50914).opacity(0.35), radius: 12)

        case .youtube:
            HStack(spacing: h * 0.05) {
                ZStack {
                    RoundedRectangle(cornerRadius: h * 0.075, style: .continuous)
                        .fill(Color(hex: 0xFF0033))
                        .frame(width: h * 0.36, height: h * 0.255)
                    Image(systemName: "play.fill")
                        .font(.system(size: h * 0.12, weight: .bold))
                }
                Text("YouTube")
                    .font(.system(size: h * 0.2, weight: .bold))
                    .kerning(-h * 0.006)
            }

        case .appleTV:
            HStack(alignment: .lastTextBaseline, spacing: h * 0.015) {
                Image(systemName: "apple.logo")
                    .font(.system(size: h * 0.26, weight: .medium))
                Text("tv")
                    .font(.system(size: h * 0.34, weight: .semibold))
                    .kerning(-h * 0.01)
            }

        case .prime:
            VStack(alignment: .leading, spacing: -h * 0.04) {
                Text("prime")
                    .font(.system(size: h * 0.26, weight: .heavy))
                Text("video")
                    .font(.system(size: h * 0.17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x00A8E1))
            }

        case .tvplus:
            HStack(alignment: .center, spacing: h * 0.015) {
                Text("tv")
                    .font(.system(size: h * 0.36, weight: .heavy, design: .rounded))
                    .kerning(-h * 0.01)
                Image(systemName: "plus")
                    .font(.system(size: h * 0.24, weight: .black))
                    .foregroundStyle(Color(hex: 0xFAD604))
                    .offset(y: -h * 0.07)
            }

        case .twitch:
            HStack(spacing: h * 0.05) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: h * 0.2, weight: .bold))
                Text("twitch")
                    .font(.system(size: h * 0.26, weight: .black))
                    .italic()
            }

        case .reddit:
            HStack(spacing: h * 0.05) {
                ZStack {
                    Circle().fill(.white).frame(width: h * 0.3, height: h * 0.3)
                    Image(systemName: "face.smiling.inverse")
                        .font(.system(size: h * 0.2, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFF4500))
                }
                Text("reddit")
                    .font(.system(size: h * 0.25, weight: .heavy))
            }

        }
    }
}
