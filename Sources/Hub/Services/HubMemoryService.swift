import Darwin
import Foundation
import Observation

/// Hub'ın RAM kullanımı. Web sayfaları (Netflix, YouTube…) Hub'ın içinde değil, macOS'un ayrı
/// WebKit süreçlerinde çalışır; Etkinlik Monitörü'nün yaptığı gibi bu süreçlerin "sorumlu"
/// uygulamasına bakıp Hub'a ait olanları toplar. Değerler Etkinlik Monitörü'ndeki "Bellek" sütunuyla aynıdır.
@Observable @MainActor
final class HubMemoryService {
    struct Slice: Identifiable, Hashable {
        enum Kind: Hashable { case app, web(tileID: String), shared }
        let kind: Kind
        let bytes: UInt64
        var id: Kind { kind }
    }

    var slices: [Slice] = []
    var total: UInt64 = 0
    var updated = false

    /// webProcesses: açık web servisi → o sayfanın WebKit süreci.
    func refresh(webProcesses: [String: pid_t]) {
        Task.detached(priority: .utility) {
            let result = Self.measure(webProcesses: webProcesses)
            await MainActor.run {
                self.slices = result
                self.total = result.reduce(0) { $0 + $1.bytes }
                self.updated = true
            }
        }
    }

    nonisolated private static func measure(webProcesses: [String: pid_t]) -> [Slice] {
        let me = getpid()
        var slices = [Slice(kind: .app, bytes: footprint(me) ?? 0)]
        guard let responsible = responsibleLookup else { return slices }

        let tileByPID = Dictionary(webProcesses.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var perTile: [String: UInt64] = [:]
        var shared: UInt64 = 0
        for pid in allPIDs() where pid != me && responsible(pid) == me {
            let bytes = footprint(pid) ?? 0
            if let tile = tileByPID[pid] { perTile[tile, default: 0] += bytes } else { shared += bytes }
        }
        slices += perTile.sorted { $0.value > $1.value }.map { Slice(kind: .web(tileID: $0.key), bytes: $0.value) }
        if shared > 0 { slices.append(Slice(kind: .shared, bytes: shared)) }
        return slices
    }

    /// Etkinlik Monitörü'nün de kullandığı sistem işlevi; bulunamazsa yalnızca Hub'ın kendi süreci ölçülür.
    nonisolated private static let responsibleLookup: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    nonisolated private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(0, count)))).filter { $0 > 0 }
    }

    /// Etkinlik Monitörü'ndeki "Bellek" değeri (phys_footprint).
    nonisolated private static func footprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    /// 1 GB altı "845 MB", üstü "1,3 GB".
    nonisolated static func format(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1024 { return "\(Int(mb.rounded())) MB" }
        let gb = mb / 1024
        return (formatter.string(from: NSNumber(value: gb)) ?? String(format: "%.1f", gb)) + " GB"
    }

    nonisolated private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f
    }()
}
