import Foundation

nonisolated protocol AudioCapturing: Sendable {
    var permissionStatus: MicrophonePermissionStatus { get async }
    func requestPermission() async -> MicrophonePermissionStatus
    func start(onBuffer: @Sendable @escaping (AudioBuffer) -> Void) async throws
    func stop() async
}
