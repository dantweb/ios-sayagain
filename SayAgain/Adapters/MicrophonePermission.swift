import Foundation
import AVFAudio

nonisolated enum MicrophonePermission {
    static func status() -> MicrophonePermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined: return .notDetermined
        case .denied:       return .denied
        case .granted:      return .granted
        @unknown default:   return .notDetermined
        }
    }

    static func request() async -> MicrophonePermissionStatus {
        let granted = await AVAudioApplication.requestRecordPermission()
        return granted ? .granted : .denied
    }
}
