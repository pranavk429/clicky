// Tests/ClickyAudioTests/WakeWordListenerTests.swift
import XCTest
@testable import ClickyAudio

final class WakeWordListenerTests: XCTestCase {

    // MARK: Matching (pure logic — no speech APIs are exercised)

    func testEveryDefaultVariantMatchesItsPlainTranscript() {
        let listener = WakeWordListener()
        for phrase in WakeWordListener.defaultPhrases {
            XCTAssertTrue(listener.matchesWakePhrase(phrase), "default variant \"\(phrase)\" must match")
        }
    }

    func testEveryDefaultVariantMatchesInsideASentenceWithCaseAndPunctuation() {
        let listener = WakeWordListener()
        for phrase in WakeWordListener.defaultPhrases {
            let transcript = "Hey \(phrase.uppercased()), please open Safari!"
            XCTAssertTrue(listener.matchesWakePhrase(transcript), "variant \"\(phrase)\" must survive normalization")
        }
    }

    func testCasePunctuationAndWhitespaceAreNormalized() {
        let listener = WakeWordListener()
        XCTAssertTrue(listener.matchesWakePhrase("Clicky"))
        XCTAssertTrue(listener.matchesWakePhrase("CLICKY!"))
        XCTAssertTrue(listener.matchesWakePhrase("  clicky??  "))
        XCTAssertTrue(listener.matchesWakePhrase("...clicky..."))
        XCTAssertTrue(listener.matchesWakePhrase("clicky\n"))
        XCTAssertTrue(listener.matchesWakePhrase("hey,\tclicky — are you there?"))
    }

    func testNormalizeTranscriptStripsPunctuationAndCollapsesWhitespace() {
        XCTAssertEqual(WakeWordListener.normalizeTranscript("  Hey, CLICKY!!  "), "hey clicky")
        XCTAssertEqual(WakeWordListener.normalizeTranscript("clicky\n\tclick e"), "clicky click e")
        XCTAssertEqual(WakeWordListener.normalizeTranscript("..."), "")
        XCTAssertEqual(WakeWordListener.normalizeTranscript(""), "")
    }

    func testClickAloneAndNearMissesDoNotMatch() {
        let listener = WakeWordListener()
        // "click" is an ordinary command word; it does not contain any variant.
        for transcript in ["click", "click here", "quickly", "clique", "clicker", "klick", "cli", ""] {
            XCTAssertFalse(listener.matchesWakePhrase(transcript), "\"\(transcript)\" must not wake")
        }
    }

    func testSubstringContainmentIsDeliberatelyAccepted() {
        // Documented trade-off: matching is `transcript.contains(phrase)`, so a transcript
        // that merely embeds a variant wakes the listener. "unclicky" contains "clicky"
        // and therefore matches. Accepted: a missed wake costs more than this exotic
        // false positive, and the session/confirmation gates still contain any
        // unintended action.
        let listener = WakeWordListener()
        XCTAssertTrue(listener.matchesWakePhrase("unclicky"))
        XCTAssertTrue(listener.matchesWakePhrase("clickyboard"))
    }

    func testClickIsDeliberatelyNotAWakeVariant() {
        XCTAssertFalse(WakeWordListener.defaultPhrases.contains("click"))
    }

    func testCustomConfigurationReplacesDefaults() {
        let custom = WakeWordListener(
            configuration: WakeWordListener.Configuration(phrases: ["hey clicky"], debounceSeconds: 1.0))
        XCTAssertTrue(custom.matchesWakePhrase("Hey, Clicky!"))
        XCTAssertFalse(custom.matchesWakePhrase("clicky"), "with a custom list, only configured phrases match")
        XCTAssertFalse(custom.matchesWakePhrase("hey there"))
    }

    func testNonLatinTranscriptDoesNotMatchOrCrash() {
        let listener = WakeWordListener()
        XCTAssertFalse(listener.matchesWakePhrase("क्लिकी"))
        XCTAssertFalse(listener.matchesWakePhrase("क्लिकी क्लिकी"))
    }

    func testConfigurationDefaults() {
        let configuration = WakeWordListener.Configuration()
        XCTAssertEqual(configuration.phrases, WakeWordListener.defaultPhrases)
        XCTAssertEqual(configuration.debounceSeconds, 2.0)
        XCTAssertEqual(WakeWordListener.defaultPhrases.count, 9)
        for phrase in WakeWordListener.defaultPhrases {
            XCTAssertEqual(phrase, phrase.lowercased(), "default variants must be pre-normalized")
        }
    }

    // MARK: Debounce (pure helper)

    func testDebouncerFiresOnceThenSwallowsRepeatsInsideInterval() {
        var debouncer = WakeWordDebouncer(interval: 2.0)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertTrue(debouncer.shouldFire(now: t0))
        XCTAssertFalse(debouncer.shouldFire(now: t0.addingTimeInterval(0.01)))
        XCTAssertFalse(debouncer.shouldFire(now: t0.addingTimeInterval(1.99)))
        XCTAssertTrue(debouncer.shouldFire(now: t0.addingTimeInterval(2.0)), "interval boundary releases")
        XCTAssertFalse(debouncer.shouldFire(now: t0.addingTimeInterval(2.5)))
    }

    func testDebouncerResetFiresImmediately() {
        var debouncer = WakeWordDebouncer(interval: 2.0)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertTrue(debouncer.shouldFire(now: t0))
        XCTAssertFalse(debouncer.shouldFire(now: t0.addingTimeInterval(0.5)))
        debouncer.reset()
        XCTAssertTrue(debouncer.shouldFire(now: t0.addingTimeInterval(0.6)))
    }

    func testDebouncerZeroIntervalNeverBlocks() {
        var debouncer = WakeWordDebouncer(interval: 0)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertTrue(debouncer.shouldFire(now: t0))
        XCTAssertTrue(debouncer.shouldFire(now: t0))
    }

    // MARK: Permission + support (never asserts availability in CI)

    func testIsSupportedIsACapabilityCheckIndependentOfPermission() {
        // isSupported is a capability check (availability + on-device assets) and
        // must NOT depend on permission — the app's launch path relies on reaching
        // the permission-request flow on first run. No availability assertion by
        // design; this is a smoke check that the call is safe without a grant.
        _ = WakeWordListener.isSupported
    }

    func testStartThrowsPermissionDeniedWhenUnauthorized() throws {
        try XCTSkipIf(WakeWordListener.hasSpeechPermission,
                      "Speech Recognition already authorized on this host")
        let listener = WakeWordListener()
        XCTAssertThrowsError(try listener.start()) { error in
            XCTAssertEqual(error as? WakeWordError, .permissionDenied)
        }
    }

    func testLifecycleCallsAreRepeatableAndSafeBeforeStart() {
        let listener = WakeWordListener()
        listener.pause()
        listener.pause()
        listener.resume()
        listener.stop()
        listener.stop()
        // No assertion: the contract is "does not crash / does not deadlock", which
        // XCTest enforces by completing the test.
    }
}
