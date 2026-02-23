import AppKit

@MainActor
protocol HotKeyControlling: AnyObject {
    var onHotKeyPressed: (() -> Void)? { get set }
    func register()
    func unregister()
}

extension GlobalHotKeyController: HotKeyControlling {}

@MainActor
protocol LocalKeyEventMonitoring {
    func addLocalKeyDownMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any
    func removeMonitor(_ monitor: Any)
}

@MainActor
private struct NSEventLocalKeyEventMonitor: LocalKeyEventMonitoring {
    func addLocalKeyDownMonitor(handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handler) as Any
    }

    func removeMonitor(_ monitor: Any) {
        NSEvent.removeMonitor(monitor)
    }
}

@MainActor
final class PromptImproverAppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyController: any HotKeyControlling
    private let mainWindowController: any MainWindowControlling
    private let keyEventMonitor: any LocalKeyEventMonitoring
    private var keyDownMonitor: Any?

    override init() {
        self.hotKeyController = GlobalHotKeyController()
        self.mainWindowController = MainWindowController.shared
        self.keyEventMonitor = NSEventLocalKeyEventMonitor()
        super.init()
    }

    init(
        hotKeyController: any HotKeyControlling,
        mainWindowController: any MainWindowControlling,
        keyEventMonitor: any LocalKeyEventMonitoring
    ) {
        self.hotKeyController = hotKeyController
        self.mainWindowController = mainWindowController
        self.keyEventMonitor = keyEventMonitor
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKeyController.onHotKeyPressed = {
            Task { @MainActor in
                self.mainWindowController.toggleMainWindow(openWindowAction: nil)
            }
        }
        hotKeyController.register()
        installKeyDownMonitor()
    }

    func applicationDidResignActive(_ notification: Notification) {
        mainWindowController.hideMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowController.openMainWindow(openWindowAction: nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeKeyDownMonitor()
        hotKeyController.unregister()
    }

    private func installKeyDownMonitor() {
        guard keyDownMonitor == nil else {
            return
        }

        keyDownMonitor = keyEventMonitor.addLocalKeyDownMonitor { [mainWindowController] event in
            mainWindowController.handleMainWindowEscape(event)
        }
    }

    private func removeKeyDownMonitor() {
        guard let keyDownMonitor else {
            return
        }

        keyEventMonitor.removeMonitor(keyDownMonitor)
        self.keyDownMonitor = nil
    }
}
