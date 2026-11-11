// Hub ikonunu çizer: swift Scripts/make-icon.swift Resources
// Çıktı: Resources/AppIcon.icns
import AppKit
import SwiftUI

struct HubIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.16),
                                              Color(red: 0.20, green: 0.10, blue: 0.40)],
                                     startPoint: .top, endPoint: .bottom))
            RadialGradient(colors: [Color(red: 0.35, green: 0.55, blue: 1).opacity(0.55), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 700)
                .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))

            VStack(spacing: 44) {
                HStack(spacing: 44) {
                    tile(Color(red: 0.40, green: 0.75, blue: 0.96), focused: true)
                    tile(Color(red: 0.90, green: 0.04, blue: 0.08))
                }
                HStack(spacing: 44) {
                    tile(Color(red: 0.11, green: 0.73, blue: 0.33))
                    tile(Color(red: 0.57, green: 0.27, blue: 1.0))
                }
            }
        }
        .frame(width: 824, height: 824)
        .frame(width: 1024, height: 1024)
    }

    func tile(_ color: Color, focused: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 56, style: .continuous)
            .fill(LinearGradient(colors: [color, color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 270, height: 200)
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: 56, style: .continuous).strokeBorder(.white, lineWidth: 16)
                }
            }
            .scaleEffect(focused ? 1.1 : 1)
            .shadow(color: .black.opacity(0.35), radius: focused ? 30 : 12, y: focused ? 18 : 8)
    }
}

MainActor.assumeIsolated {
    let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = base * scale
            let renderer = ImageRenderer(content: HubIcon())
            renderer.scale = CGFloat(px) / 1024
            guard let cg = renderer.cgImage else { fatalError("render failed") }
            let rep = NSBitmapImageRep(cgImage: cg)
            let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
            try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
        }
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
    try! task.run()
    task.waitUntilExit()
    print(task.terminationStatus == 0 ? "AppIcon.icns yazıldı" : "iconutil başarısız")
}
