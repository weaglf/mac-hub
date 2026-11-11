import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Kenarlıksız pencere klavye odağı alabilsin diye.
final class HubWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = HubStore()
    private var window: HubWindow!
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var scrollMonitor: Any?
    private var hotKey: HotKey?
    private var gamepad: GamepadInput?

    /// HUB_SNAPSHOT=/yol.png verilirse pencere ekran dışında açılır, görüntüsü kaydedilir ve uygulama kapanır.
    private let snapshotPath = ProcessInfo.processInfo.environment["HUB_SNAPSHOT"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.snapshotMode = snapshotPath != nil
        buildMenu()

        let screen = NSScreen.main ?? NSScreen.screens[0]
        var frame = screen.frame
        if snapshotPath != nil { frame.origin.x = -frame.width - 6000 }

        window = HubWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.managed, .fullScreenNone]

        store.screenSize = screen.frame.size
        store.safeTop = screen.safeAreaInsets.top
        store.onSummon = { [weak self] in self?.summon() }
        store.onPresentationChange = { [weak self] in self?.updatePresentation() }

        let root = HubRootView()
            .environment(store)
            .environment(\.locale, Locale(identifier: "tr_TR"))
        window.contentView = NSHostingView(rootView: root)
        window.makeKeyAndOrderFront(nil)

        store.start()
        installMonitors()
        gamepad = GamepadInput { [weak self] action in self?.store.handle(action, fromGamepad: true) }

        if let path = snapshotPath {
            store.applyDebugState(ProcessInfo.processInfo.environment["HUB_STATE"] ?? "")
            let delay = Double(ProcessInfo.processInfo.environment["HUB_SNAPSHOT_DELAY"] ?? "") ?? 4
            if let later = ProcessInfo.processInfo.environment["HUB_STATE_LATER"] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay / 2) { [weak self] in self?.store.applyDebugState(later) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.snapshot(to: path) }
            return
        }

        // ⌃⌥H: Hub'ı her yerden öne getirir.
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.summon()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreen() }
        }

        // Başka bir uygulama öne geçince (Hub etkin olsun olmasın) pencereyi sakla.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.hideIfInBackground() }
        }

        NSApp.activate()
        // macOS açılışta Hub'ı öne almadıysa pencere başka uygulamaların arkasında kalmasın.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if !NSApp.isActive { self?.hideIfInBackground() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard snapshotPath == nil else { return }
        // Başka uygulamadayken saklanan pencere, Hub'a dönünce (⌘Tab, Dock, ⌃⌥H, açtığın uygulama kapanınca) geri gelir.
        if !window.isVisible { window.makeKeyAndOrderFront(nil) }
        updatePresentation()
        store.isActive = true
        store.didBecomeActive()
    }

    /// Ana ekranda Dock ve menü çubuğu otomatik gizlenir. Web oynatıcıda tamamen gizlenir:
    /// yoksa fare en üste gidince inen menü çubuğu "Ana Ekran" şeridinin üstünü kapatıyor.
    private func updatePresentation() {
        guard snapshotPath == nil, NSApp.isActive else { return }
        let options: NSApplication.PresentationOptions = store.webSession == nil
            ? [store.settings.hideDock ? .hideDock : .autoHideDock, .autoHideMenuBar]
            : [.hideDock, .hideMenuBar]
        if NSApp.presentationOptions != options { NSApp.presentationOptions = options }
    }

    func applicationDidResignActive(_ notification: Notification) {
        store.isActive = false
        store.edgeScroll = nil
        hideIfInBackground()
    }

    /// Claude gibi başka bir uygulama kullanılırken Hub'ın tam ekran penceresi arkada görünmesin.
    private func hideIfInBackground() {
        guard snapshotPath == nil, store.settings.hideWhenInactive, window.isVisible else { return }
        window.orderOut(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        summon()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Pencere

    /// Hub'ı öne getirir. Pencere, macOS Hub'ı gerçekten öne aldığında (applicationDidBecomeActive) gösterilir;
    /// böylece öne alınamadığı durumda başka uygulamaların arkasında yarım görünmez.
    private func summon() {
        if NSApp.isActive || !store.settings.hideWhenInactive { window.makeKeyAndOrderFront(nil) }
        NSApp.activate()
    }

    private func fitToScreen() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(screen.frame, display: true)
        store.screenSize = screen.frame.size
        store.safeTop = screen.safeAreaInsets.top
    }

    private func snapshot(to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        exit(0)
    }

    // MARK: - Klavye ve fare

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateEdgeScroll(event)
            return event
        }
        // Ana ekranda satırlar trackpad/tekerlekle kaydırılmaz; kaydırma kenar dokunuşuyla olur.
        // Web sayfaları, Ayarlar ve not yazarken kaydırma normal çalışır.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self, self.store.webSession == nil, self.store.overlay == nil, !self.isEditingText else { return event }
            return nil
        }
    }

    /// İmleç ekranın sol/sağ kenarındaysa, hizasındaki satırı o yöne kaydırır.
    private func updateEdgeScroll(_ event: NSEvent) {
        let zone: CGFloat = 24
        let point = event.locationInWindow
        let width = window.frame.width
        let y = window.frame.height - point.y   // SwiftUI koordinatı: üstten
        var next: EdgeScroll?
        if store.webSession == nil, store.overlay == nil {
            let direction = point.x <= zone ? -1 : point.x >= width - zone ? 1 : 0
            if direction != 0, let row = store.rowFrames.first(where: { $0.value.minY <= y && y <= $0.value.maxY })?.key {
                next = EdgeScroll(row: row, direction: direction)
            }
        }
        if store.edgeScroll != next { store.edgeScroll = next }
    }

    private var isEditingText: Bool {
        window.firstResponder is NSText
    }

    /// true dönerse olay tüketilir.
    private func handleKey(_ event: NSEvent) -> Bool {
        // Web oynatıcı açıkken tuşlar sayfaya gider; çıkış ⌘W ile menüden.
        if store.webSession != nil { return false }

        let mods = event.modifierFlags.intersection([.command, .option, .control])

        if isEditingText {
            if event.keyCode == UInt16(kVK_Escape) {
                window.makeFirstResponder(nil)
                store.editingNoteID = nil
                return true
            }
            return false
        }

        if mods == .option {
            switch Int(event.keyCode) {
            case kVK_LeftArrow: store.handle(.moveLeft); return true
            case kVK_RightArrow: store.handle(.moveRight); return true
            default: return false
            }
        }
        guard mods.isEmpty else { return false }

        let action: InputAction
        switch Int(event.keyCode) {
        case kVK_LeftArrow: action = .left
        case kVK_RightArrow: action = .right
        case kVK_UpArrow: action = .up
        case kVK_DownArrow: action = .down
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space: action = .select
        case kVK_Escape: action = .back
        case kVK_Delete, kVK_ForwardDelete: action = .delete
        default: return false
        }
        NSCursor.setHiddenUntilMouseMoves(true)
        store.handle(action)
        return true
    }

    // MARK: - Menü

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ayarlar…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Widget Ekle…", action: #selector(addWidget), keyEquivalent: "n")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hub'ı Gizle", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hub'dan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Düzen")
        editMenu.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Görünüm")
        viewMenu.addItem(withTitle: "Ana Ekrana Dön", action: #selector(goHome), keyEquivalent: "w")
        viewMenu.addItem(withTitle: "Kapat ve Ana Ekrana Dön", action: #selector(closeWeb), keyEquivalent: "W")
        viewMenu.addItem(withTitle: "Geri", action: #selector(webBack), keyEquivalent: "[")
        viewMenu.addItem(withTitle: "İleri", action: #selector(webForward), keyEquivalent: "]")
        viewMenu.addItem(withTitle: "Yenile", action: #selector(webReload), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Tarayıcıda Aç", action: #selector(webOpenInBrowser), keyEquivalent: "o")
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        NSApp.mainMenu = main
    }

    @objc private func openSettings() { store.toggleSettings() }
    @objc private func addWidget() { store.openPicker() }
    @objc private func goHome() { store.goHome() }
    @objc private func closeWeb() { store.closeCurrentWeb() }
    @objc private func webBack() { store.webCommand(.back) }
    @objc private func webForward() { store.webCommand(.forward) }
    @objc private func webReload() { store.webCommand(.reload) }
    @objc private func webOpenInBrowser() { store.webCommand(.openInBrowser) }
}
