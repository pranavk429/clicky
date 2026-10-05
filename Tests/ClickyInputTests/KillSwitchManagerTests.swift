// Tests/ClickyInputTests/KillSwitchManagerTests.swift
import XCTest
@testable import ClickyInput

final class KillSwitchManagerTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []
        weak var manager: KillSwitchManager?
        func record(_ event: String) { lock.lock(); recorded.append(event); lock.unlock() }
        func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    }
    private func makeManager(_ recorder: Recorder) -> KillSwitchManager {
        let manager = KillSwitchManager(hooks: .init(
            stopPlayback: { recorder.record("stopPlayback(interrupted=\(recorder.manager?.isInterrupted == true))") },
            releaseSyntheticInput: { recorder.record("releaseInput") },
            presentBanner: { recorder.record("banner(\($0))") },
            stopSession: { recorder.record("stopSession") }))
        recorder.manager = manager
        return manager
    }
    func testVoiceBargeInStopsPlaybackWithLatchAlreadySet() {
        let recorder = Recorder()
        let manager = makeManager(recorder)
        XCTAssertTrue(manager.triggerBargeIn(source: .voiceOnset))
        XCTAssertEqual(recorder.snapshot(), ["stopPlayback(interrupted=true)"])
        XCTAssertTrue(manager.isInterrupted)
        XCTAssertEqual(manager.lastTriggerSource, .voiceOnset)
    }
    func testKillSwitchRunsAllHooksInOrderAndPostsNotification() {
        let recorder = Recorder()
        let manager = makeManager(recorder)
        let notified = expectation(forNotification: KillSwitchManager.notificationName, object: nil)
        XCTAssertTrue(manager.triggerKillSwitch(source: .hotKey))
        XCTAssertEqual(recorder.snapshot(),
                       ["stopPlayback(interrupted=true)", "releaseInput", "banner(Clicky stopped (⌘⇧X))", "stopSession"])
        wait(for: [notified], timeout: 1)
    }
    func testKillSwitchIsIdempotentUntilReset() {
        let recorder = Recorder()
        let manager = makeManager(recorder)
        XCTAssertTrue(manager.triggerKillSwitch(source: .hotKey))
        XCTAssertFalse(manager.triggerKillSwitch(source: .hotKey))
        XCTAssertFalse(manager.triggerBargeIn())
        XCTAssertEqual(recorder.snapshot().count, 4)
        manager.reset()
        XCTAssertFalse(manager.isInterrupted)
        XCTAssertTrue(manager.triggerBargeIn())
    }
    func testLatencyAnchorRecordedOnlyWhenProvided() {
        let manager = makeManager(Recorder())
        XCTAssertTrue(manager.triggerBargeIn(source: .voiceOnset, onset: ContinuousClock.now - .milliseconds(120)))
        let latency = manager.lastBargeInMilliseconds
        XCTAssertNotNil(latency)
        XCTAssertGreaterThanOrEqual(latency ?? 0, 110)
        XCTAssertLessThan(latency ?? .infinity, 500)
        manager.reset()
        XCTAssertTrue(manager.triggerKillSwitch(source: .hotKey))
        XCTAssertNil(manager.lastBargeInMilliseconds, "hotkey path has no onset anchor")
    }
}
