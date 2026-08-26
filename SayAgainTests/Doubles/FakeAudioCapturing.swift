import Foundation
@testable import SayAgain

final class FakeAudioCapturing: AudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var _permission: MicrophonePermissionStatus
    private var onBuffer: (@Sendable (AudioBuffer) -> Void)?
    private(set) var isRunning: Bool = false
    private(set) var stopCallCount: Int = 0

    init(permission: MicrophonePermissionStatus = .granted) {
        self._permission = permission
    }

    var permissionStatus: MicrophonePermissionStatus {
        get async {
            lock.lock(); defer { lock.unlock() }
            return _permission
        }
    }

    func requestPermission() async -> MicrophonePermissionStatus {
        lock.lock(); defer { lock.unlock() }
        if _permission == .notDetermined { _permission = .granted }
        return _permission
    }

    func setPermission(_ status: MicrophonePermissionStatus) {
        lock.lock(); defer { lock.unlock() }
        _permission = status
    }

    func start(onBuffer: @Sendable @escaping (AudioBuffer) -> Void) async throws {
        lock.lock()
        self.onBuffer = onBuffer
        self.isRunning = true
        lock.unlock()
    }

    func stop() async {
        lock.lock()
        self.onBuffer = nil
        self.isRunning = false
        self.stopCallCount += 1
        lock.unlock()
    }

    func inject(_ buffer: AudioBuffer) {
        lock.lock()
        let callback = self.onBuffer
        lock.unlock()
        callback?(buffer)
    }
}
