import AppKit
import Combine
import SpectrumCore

final class SpectrumModel: ObservableObject {
    enum CaptureState {
        case stopped, starting, running, failed(String)
    }

    @Published private(set) var state: CaptureState = .stopped
    @Published private(set) var frame = SpectrumFrame.silence()
    @Published var style: SpectrumStyle { didSet { defaults.set(style.rawValue, forKey: "style") } }
    @Published var palette: SpectrumPalette { didSet { defaults.set(palette.rawValue, forKey: "palette") } }
    @Published var sensitivity: Double { didSet { defaults.set(sensitivity, forKey: "sensitivity") } }
    @Published var overlayOpacity: Double { didSet { defaults.set(overlayOpacity, forKey: "overlayOpacity") } }
    @Published var overlayVisible = false
    @Published var overlayLocked = false

    private let defaults = UserDefaults.standard
    private let capture = SystemAudioCapture()
    private let analyzer = SpectrumAnalyzer()
    private let processingQueue = DispatchQueue(label: "dev.audiospectrum.analysis", qos: .userInitiated)
    private var generation = UUID()
    private var timer: Timer?
    private var lastFrameAt = Date.distantPast
    // Accessed only on processingQueue.
    private var lastPublishedAt = Date.distantPast

    init() {
        style = SpectrumStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .circular
        palette = SpectrumPalette(rawValue: defaults.string(forKey: "palette") ?? "") ?? .mint
        let storedSensitivity = defaults.double(forKey: "sensitivity")
        sensitivity = storedSensitivity > 0 ? min(3, max(0.5, storedSensitivity)) : 1.4
        let storedOpacity = defaults.double(forKey: "overlayOpacity")
        overlayOpacity = storedOpacity > 0 ? min(1, max(0.2, storedOpacity)) : 0.9
    }

    var isRunning: Bool { if case .running = state { return true }; return false }
    var isStarting: Bool { if case .starting = state { return true }; return false }
    var errorMessage: String? { if case let .failed(message) = state { return message }; return nil }
    var statusText: String {
        switch state {
        case .stopped: return "停止中"
        case .starting: return "接続中…"
        case .running: return frame.rmsDB > -90 ? "取得中" : "再生音を待っています"
        case .failed: return "接続できませんでした"
        }
    }
    var levelText: String { frame.rmsDB > -99 ? String(format: "%.0f dBFS", frame.rmsDB) : "−∞ dBFS" }

    func toggleCapture() { isRunning ? stop() : start() }

    func start() {
        guard !isRunning, !isStarting else { return }
        state = .starting
        let token = UUID()
        generation = token
        processingQueue.async { [weak self] in
            self?.analyzer.reset()
            self?.lastPublishedAt = .distantPast
        }
        capture.onSamples = { [weak self] channels, sampleRate in
            guard let self else { return }
            self.processingQueue.async { [weak self] in
                guard let self, let next = self.analyzer.consume(channels: channels, sampleRate: sampleRate) else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastPublishedAt) >= 1.0 / 30 else { return }
                self.lastPublishedAt = now
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token, self.isRunning else { return }
                    self.lastFrameAt = now
                    self.frame = next
                }
            }
        }
        capture.onError = { [weak self] error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.stop()
                self.state = .failed(error.localizedDescription)
            }
        }
        do {
            try capture.start()
            state = .running
            lastFrameAt = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self, self.isRunning else { return }
                if Date().timeIntervalSince(self.lastFrameAt) > 0.5 {
                    self.frame = .silence()
                }
            }
        } catch {
            capture.stop()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        generation = UUID()
        timer?.invalidate()
        timer = nil
        capture.stop()
        capture.onSamples = nil
        capture.onError = nil
        frame = .silence()
        state = .stopped
    }

    func openAudioPrivacy() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
