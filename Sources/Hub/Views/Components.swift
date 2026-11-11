import SwiftUI

/// TV'deki gibi odaklanınca büyüyen, beyaz çerçeve ve gölge alan öğe.
struct FocusLift: ViewModifier {
    let focused: Bool
    var scale: CGFloat = 1.08
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.95 : 0), lineWidth: 3)
            }
            .shadow(color: .black.opacity(focused ? 0.55 : 0.18), radius: focused ? 28 : 8, y: focused ? 16 : 4)
            .scaleEffect(focused ? scale : 1)
            .zIndex(focused ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.72), value: focused)
    }
}

extension View {
    /// Kaydırma hedefi: öğenin satır içindeki yerini EdgeScrollRow'a bildirir.
    /// Satır, klavyeyle seçilen öğeyi bu ölçüye göre kenar boşluğu bırakarak görünür tutar.
    func scrollTarget(_ id: String) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: ScrollTargetFrames.self,
                                       value: [id: geo.frame(in: .named(ScrollTargetFrames.space))])
            }
        }
    }

    func focusLift(_ focused: Bool, scale: CGFloat = 1.08, cornerRadius: CGFloat = 22) -> some View {
        modifier(FocusLift(focused: focused, scale: scale, cornerRadius: cornerRadius))
    }

    /// Liquid Glass kart zemini; odaklanınca markanın rengine bürünür.
    /// Cam ayrı bir arka plan katmanında: içeriğe uygulanınca renkleri beyaza çeviriyor.
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil) -> some View {
        background {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.white.opacity(0.05))
                Color.clear
                    .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular,
                                 in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
        }
    }
}

extension View {
    /// Ayarlar ve widget seçici gibi paneller için koyu, okunaklı cam zemin.
    func panelBackground(cornerRadius: CGFloat = 36) -> some View {
        background {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(white: 0.08).opacity(0.9))
                Color.clear
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            }
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        }
    }
}

/// Uzak ya da yerel görsel; ilki yüklenemezse yedeğe geçer.
struct RemoteImage: View {
    let primary: URL?
    var fallback: URL? = nil
    var placeholderSymbol = "photo"

    var body: some View {
        AsyncImage(url: primary) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure where fallback != nil:
                AsyncImage(url: fallback) { image in
                    image.resizable().scaledToFill()
                } placeholder: { placeholder }
            default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
            Image(systemName: placeholderSymbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

struct WidgetHeader: View {
    let kind: WidgetKind
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.symbol)
            Text(kind.title.uppercased(with: Fmt.tr))
            Spacer(minLength: 4)
            if let trailing { Text(trailing).lineLimit(1) }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.white.opacity(0.55))
    }
}

/// Spotify ilerleme çubuğu; her saniye güncellenir.
struct PlaybackProgress: View {
    let spotify: SpotifyService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = spotify.currentPosition(at: context.date)
            let total = max(spotify.duration, 1)
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white).frame(width: geo.size.width * min(1, position / total))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Fmt.duration(position))
                    Spacer()
                    Text(Fmt.duration(spotify.duration))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

/// Satırdaki öğelerin, satır içeriğine göre konumları.
struct ScrollTargetFrames: PreferenceKey {
    static let space = "edgeScrollRowContent"
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
