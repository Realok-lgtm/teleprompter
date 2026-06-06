import AVFoundation
import Photos
import SwiftUI

/// Owns the capture session, records constant-frame-rate video, and saves to the camera roll.
final class CameraModel: NSObject, ObservableObject {
    enum SaveState: Equatable { case idle, saving, saved, failed }

    @Published var isRecording = false
    @Published var saveState: SaveState = .idle
    @Published var permissionDenied = false
    @Published var isFront = true
    @Published var elapsed: TimeInterval = 0

    let session = AVCaptureSession()

    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "teleprompter.camera.session")
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .front
    private var timer: Timer?

    // MARK: - Setup

    func start() {
        Task { await requestAccessAndConfigure() }
    }

    private func requestAccessAndConfigure() async {
        let cam = await AVCaptureDevice.requestAccess(for: .video)
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard cam && mic else {
            await MainActor.run { self.permissionDenied = true }
            return
        }
        sessionQueue.async { [weak self] in self?.configure() }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high

        if let device = camera(for: position),
           let input = try? AVCaptureDeviceInput(device: device) {
            if session.canAddInput(input) {
                session.addInput(input)
                videoInput = input
            }
            lockFrameRate(device, fps: 30)
        }

        if let mic = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        session.startRunning()
    }

    private func camera(for pos: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos)
    }

    /// Lock min == max frame duration so the recording is true constant frame rate (editor-friendly).
    private func lockFrameRate(_ device: AVCaptureDevice, fps: Double) {
        do {
            try device.lockForConfiguration()
            let dur = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMinFrameDuration = dur
            device.activeVideoMaxFrameDuration = dur
            device.unlockForConfiguration()
        } catch {
            // non-fatal: fall back to the camera's default timing
        }
    }

    // MARK: - Camera switching

    func flip() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            if let current = self.videoInput { self.session.removeInput(current) }
            self.position = (self.position == .front) ? .back : .front
            if let device = self.camera(for: self.position),
               let input = try? AVCaptureDeviceInput(device: device) {
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.videoInput = input
                }
                self.lockFrameRate(device, fps: 30)
            }
            self.session.commitConfiguration()
            let front = self.position == .front
            DispatchQueue.main.async { self.isFront = front }
        }
    }

    // MARK: - Recording

    func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self, !self.movieOutput.isRecording else { return }
            if let connection = self.movieOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90   // portrait
                }
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (self.position == .front)
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("take-\(Int(Date().timeIntervalSince1970)).mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self, self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    private func startTimer() {
        elapsed = 0
        timer?.invalidate()
        let start = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.elapsed = Date().timeIntervalSince(start)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Save to Photos

    private func save(_ url: URL) {
        DispatchQueue.main.async { self.saveState = .saving }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.saveState = .failed }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { ok, _ in
                DispatchQueue.main.async { self.saveState = ok ? .saved : .failed }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

extension CameraModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.isRecording = true
            self.saveState = .idle
            self.startTimer()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.stopTimer()
        }
        if let error = error as NSError?,
           (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == false {
            DispatchQueue.main.async { self.saveState = .failed }
            return
        }
        save(outputFileURL)
    }
}
