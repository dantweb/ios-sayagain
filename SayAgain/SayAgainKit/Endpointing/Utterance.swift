import Foundation

nonisolated struct Utterance: Sendable, Hashable {
    let audio: AudioBuffer
    let start: Date
    let end: Date
}
