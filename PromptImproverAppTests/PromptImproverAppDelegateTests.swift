import AppKit
import Testing
@testable import PromptImprover

@MainActor
@Suite(.serialized)
struct PromptImproverAppDelegateTests {
    @Test
    func launchWiresHotKeyAndInstallsEscapeMonitor() async {
        let hotKey = FakeHotKeyController()
        let windowController = FakeMainWindowController()
        let eventMonitor = FakeLocalKeyEventMonitor()
        let delegate = PromptImproverAppDelegate(
            hotKeyController: hotKey,
            mainWindowController: windowController,
            keyEventMonitor: eventMonitor
        )

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        #expect(hotKey.registerCallCount == 1)
        #expect(eventMonitor.addCallCount == 1)
        #expect(hotKey.onHotKeyPressed != nil)

        hotKey.onHotKeyPressed?()
        #expect(await AppAsyncTestSupport.waitUntil(condition: { windowController.toggleCallCount == 1 }))
    }

    @Test
    func resignActiveHidesMainWindow() {
        let windowController = FakeMainWindowController()
        let delegate = PromptImproverAppDelegate(
            hotKeyController: FakeHotKeyController(),
            mainWindowController: windowController,
            keyEventMonitor: FakeLocalKeyEventMonitor()
        )

        delegate.applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
        #expect(windowController.hideCallCount == 1)
    }

    @Test
    func reopenOpensMainWindowAndReturnsFalse() {
        let windowController = FakeMainWindowController()
        let delegate = PromptImproverAppDelegate(
            hotKeyController: FakeHotKeyController(),
            mainWindowController: windowController,
            keyEventMonitor: FakeLocalKeyEventMonitor()
        )

        let handled = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        #expect(handled == false)
        #expect(windowController.openCallCount == 1)
    }

    @Test
    func willTerminateRemovesMonitorAndUnregistersHotkey() {
        let hotKey = FakeHotKeyController()
        let windowController = FakeMainWindowController()
        let eventMonitor = FakeLocalKeyEventMonitor()
        let delegate = PromptImproverAppDelegate(
            hotKeyController: hotKey,
            mainWindowController: windowController,
            keyEventMonitor: eventMonitor
        )

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        #expect(hotKey.unregisterCallCount == 1)
        #expect(eventMonitor.removeCallCount == 1)
    }
}

@MainActor
private final class FakeHotKeyController: HotKeyControlling {
    var onHotKeyPressed: (() -> Void)?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    func register() {
        registerCallCount += 1
    }

    func unregister() {
        unregisterCallCount += 1
    }
}

@MainActor
private final class FakeMainWindowController: MainWindowControlling {
    private(set) var openCallCount = 0
    private(set) var hideCallCount = 0
    private(set) var toggleCallCount = 0
    private(set) var escapeCallCount = 0

    func openMainWindow(openWindowAction: (() -> Void)?) {
        openCallCount += 1
        openWindowAction?()
    }

    func hideMainWindow() {
        hideCallCount += 1
    }

    func toggleMainWindow(openWindowAction: (() -> Void)?) {
        toggleCallCount += 1
        openWindowAction?()
    }

    func handleMainWindowEscape(_ event: NSEvent) -> NSEvent? {
        escapeCallCount += 1
        return event
    }
}

@MainActor
private final class FakeLocalKeyEventMonitor: LocalKeyEventMonitoring {
    private(set) var addCallCount = 0
    private(set) var removeCallCount = 0
    private var handler: ((NSEvent) -> NSEvent?)?
    private var token: NSObject?

    func addLocalKeyDownMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        addCallCount += 1
        self.handler = handler
        let token = NSObject()
        self.token = token
        return token
    }

    func removeMonitor(_ monitor: Any) {
        if let token = token, (monitor as AnyObject) === token {
            removeCallCount += 1
        }
    }
}
