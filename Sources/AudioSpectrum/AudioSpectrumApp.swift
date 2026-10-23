import AppKit
import Combine
import SwiftUI

@main
enum AudioSpectrumApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = SpectrumModel()
    private var window: NSWindow!
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        overlay = OverlayController(model: model)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1080, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "AudioSpectrum"
        window.minSize = NSSize(width: 940, height: 668)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.center()
        window.setFrameAutosaveName("AudioSpectrumMainWindow")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "AudioSpectrum")
        statusItem.button?.toolTip = "AudioSpectrum"
        let statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        overlay.close()
    }

    @objc private func showWindow() {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggleCapture() { model.toggleCapture() }
    @objc private func toggleOverlay() { model.overlayVisible.toggle() }
    @objc private func toggleLock() { model.overlayLocked.toggle() }
    @objc private func resetOverlay() { overlay.resetPosition() }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let state = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())
        menu.addItem(item("設定ウインドウを表示", action: #selector(showWindow)))
        let captureItem = item(model.isRunning ? "停止" : "開始", action: #selector(toggleCapture))
        captureItem.isEnabled = !model.isStarting
        menu.addItem(captureItem)
        menu.addItem(.separator())
        menu.addItem(item(model.overlayVisible ? "ウインドウ表示に戻す" : "デスクトップに表示", action: #selector(toggleOverlay)))
        if model.overlayVisible {
            menu.addItem(item(model.overlayLocked ? "位置固定を解除" : "位置を固定・クリックを透過", action: #selector(toggleLock)))
            menu.addItem(item("表示位置とサイズをリセット", action: #selector(resetOverlay)))
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "AudioSpectrumを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    private func configureMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "AudioSpectrumについて", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "AudioSpectrumを隠す", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "AudioSpectrumを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(NSMenuItem(title: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "すべて選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        let captureItem = NSMenuItem()
        let captureMenu = NSMenu(title: "操作")
        captureMenu.addItem(item("開始 / 停止", action: #selector(toggleCapture), key: "r"))
        captureMenu.addItem(item("デスクトップ表示を切り替え", action: #selector(toggleOverlay), key: "d"))
        captureItem.submenu = captureMenu
        main.addItem(captureItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "ウインドウ")
        windowMenu.addItem(item("設定ウインドウを表示", action: #selector(showWindow), key: "0"))
        windowMenu.addItem(NSMenuItem(title: "しまう", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }
}
