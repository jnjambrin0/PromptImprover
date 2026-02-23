import AppKit
import Carbon.HIToolbox
import Testing
@testable import PromptImprover

@MainActor
@Suite(.serialized)
struct MainWindowControllerTests {
    @Test
    func openMainWindowUsesFallbackActionWhenNoWindowExists() {
        let environment = FakeMainWindowEnvironment()
        let controller = MainWindowController(environment: environment)

        var openCallCount = 0
        controller.setFallbackOpenWindowAction {
            openCallCount += 1
        }

        controller.openMainWindow()

        #expect(environment.activateCallCount == 1)
        #expect(openCallCount == 1)
    }

    @Test
    func toggleMainWindowHidesVisibleWindowWhenAppIsActive() {
        let window = makeWindow()
        defer { window.close() }

        let environment = FakeMainWindowEnvironment()
        environment.windows = [window]
        environment.isAppActive = true

        let controller = MainWindowController(environment: environment)
        window.makeKeyAndOrderFront(nil)
        #expect(window.isVisible)

        controller.toggleMainWindow()

        #expect(window.isVisible == false)
    }

    @Test
    func escapeHidesMainWindowAndConsumesEvent() throws {
        let window = makeWindow()
        defer { window.close() }

        let environment = FakeMainWindowEnvironment()
        environment.windows = [window]
        let controller = MainWindowController(environment: environment)
        window.makeKeyAndOrderFront(nil)

        let escapeEvent = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false,
                keyCode: UInt16(kVK_Escape)
            )
        )

        let result = controller.handleMainWindowEscape(escapeEvent)
        #expect(result == nil)
        #expect(window.isVisible == false)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }
}

@MainActor
private final class FakeMainWindowEnvironment: MainWindowEnvironment {
    var windows: [NSWindow] = []
    var isAppActive: Bool = false
    private(set) var activateCallCount = 0

    func activateApp() {
        activateCallCount += 1
    }
}
