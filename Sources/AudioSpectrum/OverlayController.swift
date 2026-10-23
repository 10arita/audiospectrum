import AppKit
import Combine
import SwiftUI

final class OverlayController {
    private let model: SpectrumModel
    private var panel: NSPanel?
    private var subscriptions = Set<AnyCancellable>()

    init(model: SpectrumModel) {
        self.model = model
        model.$overlayVisible.removeDuplicates().sink { [weak self] visible in
            guard let self else { return }
            if visible { self.show() } else { self.panel?.orderOut(nil) }
        }.store(in: &subscriptions)
        model.$overlayLocked.removeDuplicates().sink { [weak self] locked in
            self?.panel?.ignoresMouseEvents = locked
        }.store(in: &subscriptions)
    }

    private func show() {
        if panel == nil {
            let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 620, height: 400),
                                 styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            window.identifier = NSUserInterfaceItemIdentifier("AudioSpectrumOverlay")
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.minSize = NSSize(width: 280, height: 200)
            window.contentView = NSHostingView(rootView: OverlayView(model: model))
            panel = window
            resetPosition()
        }
        panel?.ignoresMouseEvents = model.overlayLocked
        panel?.orderFrontRegardless()
    }

    func resetPosition() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenFrame = screen.visibleFrame
        let width = min(620, screenFrame.width * 0.75)
        let height = min(400, screenFrame.height * 0.70)
        panel.setFrame(CGRect(x: screenFrame.midX - width / 2, y: screenFrame.midY - height / 2,
                              width: width, height: height), display: true)
        model.overlayLocked = false
    }

    func close() { panel?.close() }
}

private struct OverlayView: View {
    @ObservedObject var model: SpectrumModel
    @State private var resizeOrigin: CGRect?

    var body: some View {
        ZStack {
            SpectrumCanvas(bands: model.frame.bands, style: model.style, palette: model.palette,
                           sensitivity: model.sensitivity, showsGuides: false)
                .padding(model.overlayLocked ? 12 : 30)
                .opacity(model.overlayOpacity)
                .allowsHitTesting(false)
            if !model.overlayLocked {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .allowsHitTesting(false)
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        OverlayDragHandle().frame(maxWidth: .infinity, minHeight: 30)
                            .overlay(alignment: .leading) {
                                Text("ドラッグして移動").font(.system(size: 10)).allowsHitTesting(false)
                                    .padding(.leading, 12)
                            }
                        Button { model.overlayLocked = true } label: { Image(systemName: "lock.open") }
                            .help("位置を固定し、クリックを透過")
                            .accessibilityLabel("位置を固定し、クリックを透過")
                        Button { model.overlayVisible = false } label: { Image(systemName: "xmark") }
                            .help("ウインドウ表示に戻す").accessibilityLabel("ウインドウ表示に戻す")
                    }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.white)
                    .padding(.trailing, 12)
                    .background(.black.opacity(0.65), in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
                    Spacer(minLength: 0)
                    HStack {
                        Text(model.isRunning ? model.style.title : "停止中 · 設定ウインドウから開始")
                            .font(.system(size: 10)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.65), in: Capsule())
                        Spacer()
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12)).foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .gesture(DragGesture(coordinateSpace: .global)
                                .onChanged { gesture in
                                    guard let window = overlayWindow else { return }
                                    if resizeOrigin == nil { resizeOrigin = window.frame }
                                    guard let origin = resizeOrigin else { return }
                                    let width = max(280, origin.width + gesture.translation.width)
                                    let height = max(200, origin.height + gesture.translation.height)
                                    window.setFrame(CGRect(x: origin.minX, y: origin.maxY - height, width: width, height: height), display: true)
                                }
                                .onEnded { _ in resizeOrigin = nil })
                            .accessibilityLabel("オーバーレイのサイズ変更")
                            .accessibilityAdjustableAction { direction in
                                guard let window = overlayWindow else { return }
                                let delta: CGFloat = direction == .increment ? 40 : -40
                                let frame = window.frame
                                let width = max(280, frame.width + delta)
                                let height = max(200, frame.height + delta * 0.65)
                                window.setFrame(CGRect(x: frame.minX, y: frame.maxY - height, width: width, height: height), display: true)
                            }
                    }.padding(10)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var overlayWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "AudioSpectrumOverlay" }
    }
}

private struct OverlayDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}
