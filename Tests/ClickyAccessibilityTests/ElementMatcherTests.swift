import ApplicationServices
import XCTest
@testable import ClickyAccessibility

final class ElementMatcherTests: XCTestCase {
    private func element(_ title: String, role: String = "AXButton", description: String = "",
                         value: String = "", secure: Bool = false, enabled: Bool = true) -> ElementSnapshot {
        ElementSnapshot(element: AXUIElementCreateSystemWide(),
                        key: CacheKey(role: role, subrole: "", title: title, description: description),
                        frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                        isEnabled: enabled, isSecureField: secure, actions: ["AXPress"], value: value)
    }
    func testExactBeatsContainsAndDescriptionIsMatched() {
        let exact = ElementMatcher.bestMatch(for: ElementQuery(text: "Save"), in: [element("Save As"), element("Save")])
        XCTAssertEqual(exact?.snapshot.key.title, "save")
        XCTAssertEqual(exact?.score, 1.0)
        let byDescription = ElementMatcher.bestMatch(for: ElementQuery(text: "delete note"),
                                                     in: [element("", description: "Delete note"), element("Unrelated")])
        XCTAssertEqual(byDescription?.snapshot.key.description, "delete note")
    }
    func testFuzzyTokenOverlap() {
        let best = ElementMatcher.bestMatch(for: ElementQuery(text: "order submit button"),
                                            in: [element("Submit order"), element("Cancel")])
        XCTAssertEqual(best?.snapshot.key.title, "submit order")
    }
    func testRoleAwareRanking() {
        let candidates = [element("Save", role: "AXStaticText"), element("Save", role: "AXButton")]
        let byRole = ElementMatcher.ranked(candidates, for: ElementQuery(text: "Save", role: "AXButton"))
        XCTAssertEqual(byRole.first?.snapshot.key.role, "axbutton")
        XCTAssertEqual(byRole.first?.score, 1.2)
    }
    func testSecureFieldsAreNeverTargetsAndDisabledElementsLose() {
        let secureCandidates = [element("Password", role: "AXTextField", secure: true), element("Cancel")]
        XCTAssertNil(ElementMatcher.bestMatch(for: ElementQuery(text: "password"), in: secureCandidates))
        let disabled = element("Submit", enabled: false)
        let best = ElementMatcher.bestMatch(for: ElementQuery(text: "Submit"), in: [disabled, element("Submit form")])
        XCTAssertEqual(best?.snapshot.key.title, "submit form")
        XCTAssertEqual(ElementMatcher.score(query: ElementQuery(text: "Submit"), candidate: disabled), 0.5)
    }
    func testValueMatchesSearchFieldsAndKeepsRoleMultiplier() {
        // A search bar's content lives in kAXValueAttribute; the title is just
        // "Search", so before the fix "clicky repo" could never target the field.
        let search = element("Search", role: "AXTextField", value: "clicky repo")
        let best = ElementMatcher.bestMatch(for: ElementQuery(text: "clicky repo"),
                                            in: [search, element("Cancel")])
        XCTAssertEqual(best?.snapshot.value, "clicky repo")
        XCTAssertEqual(best?.score, 1.0)
        let byRole = ElementMatcher.bestMatch(for: ElementQuery(text: "clicky repo", role: "AXTextField"),
                                              in: [search])
        XCTAssertEqual(byRole?.score, 1.2)                     // role hint still multiplies value matches
    }
    func testSecureFieldValuesAreNeverMatchable() {
        let secure = element("", role: "AXTextField", value: "hunter2", secure: true)
        XCTAssertNil(ElementMatcher.bestMatch(for: ElementQuery(text: "hunter2"), in: [secure]))
        XCTAssertEqual(ElementMatcher.score(query: ElementQuery(text: "hunter2"), candidate: secure), 0)
    }
}
