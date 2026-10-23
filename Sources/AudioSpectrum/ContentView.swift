import SwiftUI

struct ContentView: View {
    @ObservedObject var model: SpectrumModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(SpectrumTheme.line)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Label("システムオーディオ", systemImage: "hifispeaker.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SpectrumTheme.secondary)
                        Spacer()
                        Text(model.overlayVisible ? "DESKTOP" : "SPECTRUM")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(SpectrumTheme.secondary)
                    }
                    stage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    stylePicker
                }
                .padding(28)
                Divider().overlay(SpectrumTheme.line)
                inspector.frame(width: 242)
            }
            Divider().overlay(SpectrumTheme.line)
            footer
        }
        .background(SpectrumTheme.background)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .frame(minWidth: 940, minHeight: 640)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform.path")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(model.palette.accent)
                .frame(width: 40, height: 40)
                .background(model.palette.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text("AudioSpectrum").font(.system(size: 21, weight: .semibold))
                Text("Macで流れる音を、かたちに。").font(.system(size: 12)).foregroundStyle(SpectrumTheme.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(model.isRunning ? model.palette.accent : SpectrumTheme.secondary).frame(width: 6, height: 6)
                Text(model.statusText).font(.system(size: 12))
            }
            .foregroundStyle(SpectrumTheme.secondary)
            Button(action: model.toggleCapture) {
                Label(model.isRunning ? "停止" : "開始", systemImage: model.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 72, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.palette.accent)
            .foregroundStyle(SpectrumTheme.background)
            .disabled(model.isStarting)
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(SpectrumTheme.surface)
            RoundedRectangle(cornerRadius: 16).strokeBorder(SpectrumTheme.line, lineWidth: 1)
            if model.overlayVisible {
                VStack(spacing: 16) {
                    Image(systemName: "rectangle.on.rectangle").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(model.palette.accent)
                    Text("デスクトップに表示中").font(.system(size: 18, weight: .medium))
                    Text("表示や色は、このウインドウから変更できます。")
                        .font(.system(size: 12)).foregroundStyle(SpectrumTheme.secondary)
                    Button("ウインドウ表示に戻す") { model.overlayVisible = false }
                        .buttonStyle(.bordered)
                }
                .padding(20)
            } else {
                VStack(spacing: 0) {
                    ZStack {
                        SpectrumCanvas(bands: model.frame.bands, style: model.style, palette: model.palette, sensitivity: model.sensitivity)
                        if model.style == .circular {
                            VStack(spacing: 7) {
                                Text(model.isRunning ? "INPUT LEVEL" : "READY")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .tracking(2).foregroundStyle(SpectrumTheme.secondary)
                                Text(model.levelText)
                                    .font(.system(size: 22, weight: .light, design: .monospaced))
                                    .contentTransition(reduceMotion ? .identity : .numericText())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    HStack {
                        Text("40 Hz")
                        Spacer()
                        Text(model.style == .circular ? "時計回りに 低音 → 高音" : "低音 → 高音")
                        Spacer()
                        Text("20 kHz")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SpectrumTheme.secondary)
                    .padding(.horizontal, 24).padding(.bottom, 18)
                }
                if !model.isRunning {
                    VStack {
                        Spacer()
                        Text(model.errorMessage == nil ? "「開始」を押し、Macで音楽や動画を再生してください。" : "音声取得の設定を確認してください。")
                            .font(.system(size: 12))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(SpectrumTheme.background.opacity(0.95), in: Capsule())
                            .padding(.bottom, 50)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var stylePicker: some View {
        HStack(spacing: 10) {
            ForEach(SpectrumStyle.allCases) { style in
                Button { model.style = style } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: style.symbol).font(.system(size: 18))
                            Spacer()
                            if model.style == style { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)) }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(style.title).font(.system(size: 13, weight: .semibold))
                            Text(style.subtitle).font(.system(size: 10)).foregroundStyle(SpectrumTheme.secondary)
                        }
                    }
                    .foregroundStyle(model.style == style ? model.palette.accent : .white)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(model.style == style ? model.palette.accent.opacity(0.08) : SpectrumTheme.surface,
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                        model.style == style ? model.palette.accent.opacity(0.65) : SpectrumTheme.line, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.style == style ? [.isSelected] : [])
                .help(style.subtitle)
            }
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("表示先")
                    Picker("表示先", selection: $model.overlayVisible) {
                        Text("ウインドウ").tag(false)
                        Text("デスクトップ").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(model.overlayVisible ? "背景透過で最前面に表示します。" : "ウインドウ内にスペクトラムを表示します。")
                        .font(.system(size: 11)).foregroundStyle(SpectrumTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.overlayVisible {
                        Toggle("位置を固定・クリックを透過", isOn: $model.overlayLocked)
                            .font(.system(size: 11)).toggleStyle(.checkbox)
                        Text("解除はメニューバーの波形アイコンから。")
                            .font(.system(size: 10)).foregroundStyle(SpectrumTheme.secondary)
                        sliderLabel("不透明度", value: "\(Int(model.overlayOpacity * 100))%")
                        Slider(value: $model.overlayOpacity, in: 0.2...1).accessibilityLabel("デスクトップ表示の不透明度")
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("カラー")
                    HStack(spacing: 12) {
                        ForEach(SpectrumPalette.allCases) { palette in
                            Button { model.palette = palette } label: {
                                Circle().fill(LinearGradient(colors: palette.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 30, height: 30)
                                    .padding(4)
                                    .overlay(Circle().stroke(model.palette == palette ? Color.white : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(palette.title)
                            .accessibilityAddTraits(model.palette == palette ? [.isSelected] : [])
                            .help(palette.title)
                        }
                    }
                    Text(model.palette.title).font(.system(size: 11)).foregroundStyle(SpectrumTheme.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sliderLabel("感度", value: String(format: "%.1f×", model.sensitivity))
                    Slider(value: $model.sensitivity, in: 0.5...3, step: 0.1).accessibilityLabel("スペクトラムの表示感度")
                    Text("音量が小さいときは感度を上げてください。再生音量は変わりません。")
                        .font(.system(size: 11)).foregroundStyle(SpectrumTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider().overlay(SpectrumTheme.line)
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("入力")
                    Text("Mac全体の再生音").font(.system(size: 12, weight: .medium))
                    Text("マイクは使用しません。音声の保存・送信は行いません。")
                        .font(.system(size: 11)).foregroundStyle(SpectrumTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    if let message = model.errorMessage {
                        Label("音声を取得できません", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                        Text(message).font(.system(size: 11)).foregroundStyle(SpectrumTheme.secondary).textSelection(.enabled)
                    } else if !model.isRunning {
                        Text("初回の開始時に、音声の取得を許可してください。")
                            .font(.system(size: 11)).foregroundStyle(SpectrumTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("音声収録の設定を開く", action: model.openAudioPrivacy)
                        .font(.system(size: 11)).buttonStyle(.link)
                }
            }
            .padding(24)
        }
        .background(SpectrumTheme.surface.opacity(0.4))
    }

    private var footer: some View {
        HStack {
            Text("\(model.style.title) / \(model.overlayVisible ? "デスクトップ" : "ウインドウ")")
            Spacer()
            Text("入力 \(model.levelText)").monospacedDigit()
            Text("·")
            Text("⌘R  開始 / 停止")
        }
        .font(.system(size: 10)).foregroundStyle(SpectrumTheme.secondary)
        .padding(.horizontal, 28).padding(.vertical, 12)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
    }
    private func sliderLabel(_ title: String, value: String) -> some View {
        HStack {
            sectionTitle(title)
            Spacer()
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(SpectrumTheme.secondary)
        }
    }
}
