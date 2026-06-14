import SwiftUI

struct ContentView: View {
    @StateObject private var camera = CameraModel()
    @StateObject private var scroller = Scroller()

    @AppStorage("script") private var script = ""
    @AppStorage("speed") private var speed = 5.0
    @AppStorage("fontSize") private var fontSize = 44.0
    @AppStorage("stackWords") private var stackWords = false
    @AppStorage("showGuide") private var showGuide = false

    @State private var showEditor = false
    @State private var editingInline = false
    @State private var showClearConfirm = false
    @State private var dragging = false
    @State private var dragStart: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @FocusState private var editorFocused: Bool
    @FocusState private var inlineFocused: Bool

    private let placeholder = "Tap anywhere to add your script"
    /// Vertical position of the red reading-line guide (fraction of screen height).
    private let guideFraction: CGFloat = 0.30

    /// What the teleprompter renders: one word per line in stack mode, with a
    /// blank line after any word that ends a sentence (. ! ?).
    private var displayScript: String {
        guard stackWords else { return script }
        let words = script.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        var lines: [String] = []
        for word in words {
            lines.append(String(word))
            if let last = word.last, ".!?".contains(last) {
                lines.append("")   // gap between sentences
            }
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            Color.black.opacity(0.28).ignoresSafeArea()

            prompter

            if showGuide && !editingInline { guideLine }

            VStack {
                if camera.isRecording { recordingPill }
                Spacer()
                controls
            }
            .padding(.top, 8)

            if camera.saveState == .reviewing { reviewOverlay }
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
            ZStack {
                if editingInline {
                    // Inline editing: cursor + keyboard directly on the camera view.
                    TextEditor(text: $script)
                        .font(promptFont)
                        .foregroundStyle(.white)
                        .tint(.white)
                        .multilineTextAlignment(.center)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.horizontal, 18)
                        .padding(.top, geo.size.height * 0.06)
                        .focused($inlineFocused)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { stopInlineEditing() }
                            }
                        }
                } else if script.isEmpty {
                    // Short hint, centered in the reading area above the controls.
                    Text(placeholder)
                        .font(promptFont)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.85), radius: 6, y: 2)
                        .padding(.horizontal, 22)
                        .frame(width: geo.size.width, height: geo.size.height * 0.66, alignment: .center)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .contentShape(Rectangle())
                        .onTapGesture { startInlineEditing() }
                } else {
                    let topPad = geo.size.height * 0.5
                    Text(displayScript)
                        .font(promptFont)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.85), radius: 6, y: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 22)
                        .fixedSize(horizontal: false, vertical: true)  // full height, no truncation
                        .padding(.top, topPad)
                        .offset(y: -scroller.offset)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { startInlineEditing() }
                        .gesture(dragGesture)
                }

                // Always-present, invisible height measurer, isolated in an
                // overlay so its full height never disturbs the visible layout.
                // Keeps maxOffset correct so Play always knows how far to scroll.
                Color.clear
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(alignment: .top) {
                        Text(displayScript.isEmpty ? " " : displayScript)
                            .font(promptFont)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 22)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(
                                GeometryReader { g in
                                    Color.clear.preference(key: HeightKey.self, value: g.size.height)
                                }
                            )
                            .opacity(0)
                    }
                    .clipped()
                    .allowsHitTesting(false)
            }
            .onPreferenceChange(HeightKey.self) { h in
                contentHeight = h
                scroller.maxOffset = max(0, h)
            }
        }
    }

    private func startInlineEditing() {
        scroller.pause()
        editingInline = true
        // Focus once the editor is in the hierarchy so the keyboard opens.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { inlineFocused = true }
    }

    private func stopInlineEditing() {
        inlineFocused = false
        editingInline = false
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
        .system(size: fontSize, weight: .bold)
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

            HStack(spacing: 10) {
                Button { scroller.restart() } label: {
                    Image(systemName: "arrow.counterclockwise").iconChip()
                }
                Button { camera.flip() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera").iconChip()
                }
                Button { stackWords.toggle() } label: {
                    Image(systemName: "text.aligncenter").iconChip(active: stackWords, tint: .blue)
                }
                Button { showGuide.toggle() } label: {
                    Image(systemName: "scope").iconChip(active: showGuide, tint: .red)
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

    private var guideLine: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.red)
                .frame(height: 3)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                .position(x: geo.size.width / 2, y: geo.size.height * guideFraction)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private var reviewOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "film")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                Text("Recording finished")
                    .font(.title2).bold()
                Text("Save it to your camera roll, or redo the take.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
                HStack(spacing: 12) {
                    Button {
                        camera.discardPending()
                    } label: {
                        Label("Redo", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(BigButton(tint: .red, filled: false))

                    Button {
                        camera.savePending()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(BigButton(tint: .blue, filled: true))
                }
                .padding(.horizontal, 30)
                .padding(.top, 6)
            }
        }
    }

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
            ZStack(alignment: .topLeading) {
                TextEditor(text: $script)
                    .font(.title3)
                    .padding(8)
                    .focused($editorFocused)
                if script.isEmpty {
                    Text("Type or paste your script here…")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Script")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .destructive) { showClearConfirm = true } label: {
                        Text("Clear")
                    }
                    .disabled(script.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showEditor = false }
                }
            }
            .confirmationDialog("Clear all text?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Clear all", role: .destructive) { script = "" }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear { editorFocused = true }
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
    func iconChip(active: Bool = false, tint: Color = .white) -> some View {
        self.font(.title3)
            .frame(width: 50, height: 50)
            .background(active ? tint : Color.white.opacity(0.16))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
