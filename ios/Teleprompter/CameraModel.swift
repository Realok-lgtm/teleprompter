import AVFoundation
import Photos
import SwiftUI

/// Owns the capture session, records constant-frame-rate video, and saves to the camera roll.
final class CameraModel: NSObject, ObservableObject {
    enum SaveState: Equatable { case idle, reviewing, saving, saved, failed }

    @Published var isRecording = false
    @Published var saveState: SaveState = .idle
    /// The just-finished take, awaiting a Save / Redo decision.
    @Published var pendingURL: URL?
    @Published var permissionDenied = false
    @Published var isFront = true
    @Published var elapsed: TimeInterval = 0

    let session = AVCaptureSession()

    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "teleprompter.camera.session")
    private var videoInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .front
    private var timer: Timer?
    /// Computes the correct upright rotation angle for the current device.
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

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
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
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
                self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
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
                // Use the device's true upright angle (not a hard-coded 90°,
                // which recorded sideways on this device).
                let angle = self.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
                if connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (self.position == .front)

                // Force H.264 (not the iPhone's default HEVC). HEVC uploads
                // unreliably to Instagram and is only tolerated by TikTok;
                // H.264 + AAC in a .mov is the format both accept cleanly.
                if self.movieOutput.availableVideoCodecTypes.contains(.h264) {
                    self.movieOutput.setOutputSettings(
                        [AVVideoCodecKey: AVVideoCodecType.h264],
                        for: connection
                    )
                }
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

    // MARK: - Save / Redo decision

    /// Save the take that's awaiting review to the camera roll.
    func savePending() {
        guard let url = pendingURL else { return }
        pendingURL = nil
        save(url)
    }

    /// Throw away the take that's awaiting review and return to filming.
    func discardPending() {
        if let url = pendingURL { try? FileManager.default.removeItem(at: url) }
        pendingURL = nil
        saveState = .idle
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
        // Hold the take and let the user choose Save or Redo.
        DispatchQueue.main.async {
            self.pendingURL = outputFileURL
            self.saveState = .reviewing
        }
    }
}
