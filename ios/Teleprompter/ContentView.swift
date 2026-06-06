import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var scroller = Scroller()

    @AppStorage("script") private var script = ""
    @AppStorage("speed") private var speed = 5.0
    @AppStorage("fontSize") private var fontSize = 44.0
    @AppStorage("fontChoice") private var fontChoice = "sans"

    @State private var showEditor = false
    @State private var dragging = false
    @State private var dragStart: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private let placeholder = "Tap the pencil to add your script.\n\nThen press Play to scroll, and Record to film.\n\nDrag up or down any time to reposition."

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            Color.black.opacity(0.28).ignoresSafeArea()

            prompter

            VStack {
                if camera.isRecording { recordingPill }
                Spacer()
                controls
            }
            .padding(.top, 8)

            if camera.saveState == .saved { savedOverlay }
            if camera.permissionDenied { permissionOverlay }
        }
        .onAppear {
            camera.start()
            scroller.speed = speed
        }
        .onChange(of: speed) { _, new in scroller.speed = new }
        .onChange(of: scroller.playing) { _, _ in updateIdleTimer() }
        .onChange(of: camera.isRecording) { _, _ in updateIdleTimer() }
        .sheet(isPresented: $showEditor) { editor }
    }

    // MARK: - Teleprompter

    private var prompter: some View {
        GeometryReader { geo in
            let topPad = geo.size.height * 0.5
            Text(script.isEmpty ? placeholder : script)
                .font(promptFont)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.85), radius: 6, y: 2)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: HeightKey.self, value: g.size.height)
                    }
                )
                .padding(.top, topPad)
                .offset(y: -scroller.offset)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture)
                .onPreferenceChange(HeightKey.self) { h in
                    contentHeight = h
                    scroller.maxOffset = max(0, h)
                }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !dragging { dragging = true; dragStart = scroller.offset }
                let p = dragStart - value.translation.height
                scroller.offset = min(max(0, p), scroller.maxOffset)
            }
            .onEnded { _ in
                dragging = false
                dragStart = scroller.offset
            }
    }

    private var promptFont: Font {
        switch fontChoice {
        case "serif": return .system(size: fontSize, weight: .bold, design: .serif)
        case "mono": return .system(size: fontSize, weight: .bold, design: .monospaced)
        case "heavy": return .system(size: fontSize, weight: .black)
        default: return .system(size: fontSize, weight: .bold)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: toggleRecord) {
                    Label(camera.isRecording ? "Stop" : "Record",
                          systemImage: camera.isRecording ? "stop.fill" : "record.circle")
                }
                .buttonStyle(BigButton(tint: .red, filled: !camera.isRecording))

                Button { scroller.toggle() } label: {
                    Label(scroller.playing ? "Pause" : "Play",
                          systemImage: scroller.playing ? "pause.fill" : "play.fill")
                }
                .buttonStyle(BigButton(tint: .blue, filled: true))
            }

            slider(title: "Speed", value: $speed, range: 1...20, step: 1, label: "\(Int(speed))")
            slider(title: "Size", value: $fontSize, range: 24...140, step: 2, label: "\(Int(fontSize))")

            HStack(spacing: 12) {
                Picker("Font", selection: $fontChoice) {
                    Text("Sans").tag("sans")
                    Text("Serif").tag("serif")
                    Text("Mono").tag("mono")
                    Text("Heavy").tag("heavy")
                }
                .pickerStyle(.segmented)

                Button { scroller.restart() } label: {
                    Image(systemName: "arrow.counterclockwise").iconChip()
                }
                Button { camera.flip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").iconChip()
                }
                Button { showEditor = true } label: {
                    Image(systemName: "pencil").iconChip()
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private func slider(title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double, label: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption).bold()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(label)
                .font(.body.monospacedDigit()).bold()
                .frame(width: 38, alignment: .trailing)
        }
    }

    // MARK: - Overlays

    private var recordingPill: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 11, height: 11)
            Text(timeString(camera.elapsed))
                .font(.subheadline.monospacedDigit()).bold()
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .foregroundStyle(.white)
    }

    private var savedOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.green)
                Text("Saved to your camera roll")
                    .font(.title2).bold()
                Text("Your video is safe. You can close this and open TikTok.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
                Button("Record another") { camera.saveState = .idle }
                    .buttonStyle(BigButton(tint: .blue, filled: true))
                    .frame(maxWidth: 220)
            }
        }
    }

    private var permissionOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill").font(.system(size: 56)).foregroundStyle(.secondary)
                Text("Camera & microphone needed").font(.title3).bold()
                Text("Enable them in Settings → Teleprompter, then reopen the app.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(BigButton(tint: .blue, filled: true))
                .frame(maxWidth: 220)
            }
        }
    }

    private var editor: some View {
        NavigationStack {
            TextEditor(text: $script)
                .font(.title3)
                .padding(8)
                .navigationTitle("Script")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showEditor = false }
                    }
                }
        }
    }

    // MARK: - Actions

    private func toggleRecord() {
        camera.isRecording ? camera.stopRecording() : camera.startRecording()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scroller.playing || camera.isRecording
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Helpers

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct BigButton: ButtonStyle {
    var tint: Color
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.bold())
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .foregroundStyle(filled ? .white : tint)
            .background(filled ? tint : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private extension Image {
    func iconChip() -> some View {
        self.font(.title3)
            .frame(width: 50, height: 50)
            .background(.white.opacity(0.16))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
