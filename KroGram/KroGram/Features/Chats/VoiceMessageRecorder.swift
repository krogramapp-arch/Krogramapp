import AVFoundation
import Combine
import Foundation

@MainActor
final class VoiceMessageRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    func start() async throws {
        let session = AVAudioSession.sharedInstance()
        let permissionGranted: Bool
        switch session.recordPermission {
        case .granted:
            permissionGranted = true
        case .denied:
            permissionGranted = false
        case .undetermined:
            permissionGranted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { continuation.resume(returning: $0) }
            }
        @unknown default:
            permissionGranted = false
        }
        guard permissionGranted else {
            throw TDError(code: -3, message: "MICROPHONE_PERMISSION_DENIED")
        }

        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        guard audioRecorder.record(forDuration: 60) else {
            try? session.setActive(false)
            throw TDError(code: -3, message: "AUDIO_RECORDING_FAILED")
        }
        recorder = audioRecorder
        recordingURL = url
        isRecording = true
    }

    func finish() throws -> (url: URL, duration: Int) {
        guard let recorder, let recordingURL else {
            throw TDError(code: -3, message: "AUDIO_RECORDING_FAILED")
        }
        let duration = Int(recorder.currentTime.rounded(.up))
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        isRecording = false
        try AVAudioSession.sharedInstance().setActive(false)
        guard duration > 0 else {
            try? FileManager.default.removeItem(at: recordingURL)
            throw TDError(code: -3, message: "AUDIO_RECORDING_TOO_SHORT")
        }
        return (recordingURL, min(duration, 60))
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
