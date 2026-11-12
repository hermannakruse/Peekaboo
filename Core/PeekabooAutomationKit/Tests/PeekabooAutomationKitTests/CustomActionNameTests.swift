import PeekabooFoundation
import Testing
@testable import PeekabooAutomationKit

/// UIKit and Catalyst apps advertise custom accessibility actions as
/// `Name:<title>\nTarget:0x0\nSelector:(null)`, not as `AX...` names, while users only know the title
/// (Apple's Home app offers "More Controls" on accessory tiles). These tests pin that a title resolves to exactly
/// the advertised action and that anything else is refused, because `action` mutates the target app.
struct CustomActionNameTests {
    private static let moreControls = "Name:More Controls\nTarget:0x0\nSelector:(null)"

    // MARK: Pre-flight check

    @Test(arguments: [
        "AXPress",
        "More Controls",
        "Mark as Read & Archive",
        "Name:More Controls\nTarget:0x0\nSelector:(null)",
    ])
    func `plausible names include AX names, titles and the advertised UIKit shape`(name: String) {
        #expect(UIAutomationService.isPlausibleActionName(name))
    }

    @Test(arguments: [
        "",
        "AXPress\u{0}",
        "AXPress\tAXCancel",
        "AXPress\rAXCancel",
        "AXPress\u{1B}[0m",
        "AXPress\u{7F}",
    ])
    func `control characters are rejected before any Accessibility call`(name: String) {
        #expect(!UIAutomationService.isPlausibleActionName(name))
    }

    @Test
    func `names longer than 128 characters are rejected`() {
        #expect(UIAutomationService.isPlausibleActionName(String(repeating: "A", count: 128)))
        #expect(!UIAutomationService.isPlausibleActionName(String(repeating: "A", count: 129)))
    }

    // MARK: Resolution against the advertised names

    @Test
    func `an advertised name is used as is`() throws {
        let advertised = ["AXPress", Self.moreControls]

        #expect(try UIAutomationService.resolveActionName("AXPress", advertised: advertised) == "AXPress")
        #expect(try UIAutomationService.resolveActionName(Self.moreControls, advertised: advertised) ==
            Self.moreControls)
    }

    @Test
    func `a custom action title resolves to the advertised long name`() throws {
        let advertised = ["AXPress", "Name:Other\nTarget:0x0\nSelector:(null)", Self.moreControls]

        #expect(try UIAutomationService.resolveActionName("More Controls", advertised: advertised) ==
            Self.moreControls)
    }

    @Test
    func `a title containing punctuation resolves when the element advertises it`() throws {
        let name = "Name:Mark as Read & Archive: now\nTarget:0x0\nSelector:(null)"

        #expect(try UIAutomationService.resolveActionName(
            "Mark as Read & Archive: now",
            advertised: [name]) == name)
    }

    /// "More" must never select "More Controls": a wrong guess would trigger a different action in the target app.
    @Test(arguments: ["More", "More Control", "More Controls ", "more controls", "Controls", "Name:More"])
    func `a title must match the Name line exactly`(requested: String) {
        // Never mapped to "More Controls": it either keeps its own name (a plain word, which the element then
        // reports as unsupported) or is refused as invalid.
        let resolved = try? UIAutomationService.resolveActionName(requested, advertised: [Self.moreControls])
        #expect(resolved != Self.moreControls)
        #expect(resolved == nil || resolved == requested)
    }

    @Test
    func `an unadvertised AX-style name is returned unchanged so the usual unsupported error applies`() throws {
        #expect(try UIAutomationService.resolveActionName("AXShowMenu", advertised: []) == "AXShowMenu")
        #expect(try UIAutomationService.resolveActionName(
            "AXShowMenu",
            advertised: [Self.moreControls]) == "AXShowMenu")
    }

    @Test(arguments: [
        "AXPress\nAXCancel",
        "Name:Only\nTarget:0x0",
        "AXPress/../AXCancel",
        "AXPress;rm",
    ])
    func `a string the element does not advertise is refused`(requested: String) {
        #expect(throws: PeekabooError.self) {
            try UIAutomationService.resolveActionName(requested, advertised: [Self.moreControls])
        }
    }

    /// Two actions with the same title: refuse and list the full names instead of silently picking one.
    @Test
    func `a title shared by several custom actions is ambiguous and lists the full names`() throws {
        let first = "Name:Dup\nTarget:0x1\nSelector:(null)"
        let second = "Name:Dup\nTarget:0x2\nSelector:(null)"

        do {
            _ = try UIAutomationService.resolveActionName("Dup", advertised: [first, second])
            Issue.record("Expected an ambiguity error")
        } catch let PeekabooError.invalidInput(message) {
            #expect(message.contains("ambiguous"))
            #expect(message.contains("Target:0x1"))
            #expect(message.contains("Target:0x2"))
        }
        // The full name still selects exactly one of them.
        #expect(try UIAutomationService.resolveActionName(second, advertised: [first, second]) == second)
    }

    // MARK: End to end with the action driver

    @MainActor
    @Test
    func `performing a custom action by title invokes the advertised long name`() throws {
        let element = ActionInputMockAutomationElement(role: "AXStaticText", actionNames: [Self.moreControls])
        let name = try UIAutomationService.resolveActionName("More Controls", advertised: element.actionNames)

        let result = try ActionInputDriver().tryPerformActionForTesting(element: element, actionName: name)

        #expect(element.performedActions == [Self.moreControls])
        #expect(result.actionName == Self.moreControls)
    }
}
