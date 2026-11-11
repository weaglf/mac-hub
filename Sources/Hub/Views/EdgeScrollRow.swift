import SwiftUI

/// Ana ekrandaki yatay satırlar (raf, uygulamalar, widget'lar).
/// - Trackpad/tekerlekle kaydırılmaz (AppDelegate bu olayları ana ekranda yutar).
/// - Fare ekranın sol/sağ kenarına dayanınca, imlecin hizasındaki satır o yöne kayar.
/// - Klavye/kumandayla odak değişince seçili öğe en az kaydırmayla görünür tutulur.
struct EdgeScrollRow<Content: View>: View {
    @Environment(HubStore.self) private var store
    let row: HomeRow
    /// Görünür tutulacak öğenin kimliği (öğede `.scrollTarget(id)` olmalı).
    let targetID: String?
    @ViewBuilder let content: Content

    @State private var position = ScrollPosition(edge: .leading)
    @State private var geometry: ScrollGeometry?
    @State private var frames: [String: CGRect] = [:]

    /// Klavyeyle seçilen öğe ile ekran kenarı arasında kalacak boşluk (içerik kenar payıyla aynı).
    private let margin: CGFloat = 64

    /// Saniyede kaç nokta kaysın.
    private let speed: CGFloat = 900

    private var direction: Int {
        guard let edge = store.edgeScroll, edge.row == row else { return 0 }
        return edge.direction
    }

    private var maxOffset: CGFloat {
        guard let g = geometry else { return 0 }
        return max(0, g.contentSize.width - g.containerSize.width)
    }

    private var canScroll: Bool {
        guard let g = geometry else { return false }
        return direction > 0 ? g.contentOffset.x < maxOffset - 1 : direction < 0 && g.contentOffset.x > 1
    }

    var body: some View {
        ScrollView(.horizontal) {
            content
                .coordinateSpace(.named(ScrollTargetFrames.space))
                .onPreferenceChange(ScrollTargetFrames.self) { frames = $0 }
        }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, new in geometry = new }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { store.rowFrames[row] = $0 }
            .onChange(of: targetID) { _, id in reveal(id, animated: true) }
            .onChange(of: frames) { old, _ in
                // Satır ilk ölçüldüğünde seçili öğe ekran dışındaysa (ör. sondaki bir öğe) görünür yap.
                if old.isEmpty { reveal(targetID, animated: false) }
            }
            .task(id: direction) { await edgeScroll() }
            .overlay(alignment: direction < 0 ? .leading : .trailing) {
                if direction != 0, canScroll { edgeHint }
            }
            .animation(.easeOut(duration: 0.2), value: direction)
    }

    /// Öğe ekranın kenarına taşıyorsa, kenarda `margin` kadar boşluk kalacak şekilde kaydırır.
    /// İlk öğe için bu, satırın tam başı demektir (içerikteki sol boşluk görünür).
    private func reveal(_ id: String?, animated: Bool) {
        guard let id, let frame = frames[id], let g = geometry else { return }
        let offset = g.contentOffset.x
        let width = g.containerSize.width
        var target = offset
        if frame.minX - margin < offset {
            target = frame.minX - margin
        } else if frame.maxX + margin > offset + width {
            target = frame.maxX + margin - width
        }
        target = min(maxOffset, max(0, target))
        guard abs(target - offset) > 0.5 else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) { position.scrollTo(x: target) }
        } else {
            position.scrollTo(x: target)
        }
    }

    /// İmleç kenarda kaldıkça her karede biraz kaydırır.
    private func edgeScroll() async {
        guard direction != 0 else { return }
        let step = speed / 60
        while !Task.isCancelled, let g = geometry {
            let target = min(maxOffset, max(0, g.contentOffset.x + CGFloat(direction) * step))
            if abs(target - g.contentOffset.x) < 0.5 { break }   // uca gelindi
            position.scrollTo(x: target)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }

    private var edgeHint: some View {
        let leading = direction < 0
        return ZStack {
            LinearGradient(colors: [.black.opacity(0.55), .clear],
                           startPoint: leading ? .leading : .trailing, endPoint: leading ? .trailing : .leading)
            Image(systemName: leading ? "chevron.left" : "chevron.right")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
                .padding(.horizontal, 18)
        }
        .frame(width: 110)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
