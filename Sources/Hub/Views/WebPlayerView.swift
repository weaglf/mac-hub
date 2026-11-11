import SwiftUI
import WebKit

/// Netflix, YouTube, Twitch, Reddit gibi servisleri Hub içinde tam ekran açar.
/// Üst şerit çentik bandını kullanır; çentiğin olduğu orta kısım boş bırakılır.
struct WebPlayerView: View {
    @Environment(HubStore.self) private var store
    let session: WebSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                bar("Ana Ekran", "chevron.left", "⌘W") { store.goHome() }
                bar("Kapat", "xmark", "⇧⌘W") { store.closeCurrentWeb() }
                bar(nil, "arrow.left", "⌘[") { store.webCommand(.back) }
                bar(nil, "arrow.right", "⌘]") { store.webCommand(.forward) }
                bar(nil, "arrow.clockwise", "⌘R") { store.webCommand(.reload) }
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.leading, 8)
                Spacer()
                bar("Tarayıcıda Aç", "safari", "⌘O") { store.webCommand(.openInBrowser) }
            }
            .padding(.horizontal, 12)
            .frame(height: max(store.safeTop, 36))
            .background(.black)

            WebViewHost(session: session)
                .id(session.id)
        }
        .background(.black)
    }

    private func bar(_ title: String?, _ symbol: String, _ shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                if let title { Text(title).font(.system(size: 12, weight: .semibold)) }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(.white.opacity(0.1), in: .capsule)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(shortcut)
    }
}

private struct WebViewHost: NSViewRepresentable {
    let session: WebSession

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let web = WebViewPool.shared.webView(for: session)
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        DispatchQueue.main.async { web.window?.makeFirstResponder(web) }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
