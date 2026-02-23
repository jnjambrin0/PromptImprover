import AppKit
import Carbon.HIToolbox

@MainActor
protocol MainWindowControlling: AnyObject {
    func openMainWindow(openWindowAction: (() -> Void)?)
    func hideMainWindow()
    func toggleMainWindow(openWindowAction: (() -> Void)?)
    func handleMainWindowEscape(_ event: NSEvent) -> NSEvent?
}

@MainActor
protocol MainWindowEnvironment {
    var windows: [NSWindow] { get }
    var isAppActive: Bool { get }
    func activateApp()
}

private struct LiveMainWindowEnvironment: MainWindowEnvironment {
    var windows: [NSWindow] { NSApp.windows }
    var isAppActive: Bool { NSApp.isActive }

    func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@MainActor
final class MainWindowController: MainWindowControlling {
    static let mainWindowSceneID = "main-window"
    static let shared = MainWindowController()

    private var fallbackOpenWindowAction: (() -> Void)?
    private let environment: any MainWindowEnvironment

    init(environment: any MainWindowEnvironment) {
        self.environment = environment
    }

    convenience init() {
        self.init(environment: LiveMainWindowEnvironment())
    }

    func setFallbackOpenWindowAction(_ action: @escaping () -> Void) {
        fallbackOpenWindowAction = action
    }

    func openMainWindow(openWindowAction: (() -> Void)? = nil) {
        environment.activateApp()

        if let window = mainWindow() {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let resolvedOpenWindowAction = openWindowAction ?? fallbackOpenWindowAction
        if let resolvedOpenWindowAction {
            resolvedOpenWindowAction()
            Task { @MainActor in
                if let window = self.mainWindow() {
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
                    window.makeKeyAndOrderFront(nil)
                }
            }
            return
        }

        Logging.debug("Unable to open main window: no openWindow action is available.")
    }

    func hideMainWindow() {
        guard let window = mainWindow(), window.isVisible else {
            return
        }
        window.orderOut(nil)
    }

    func toggleMainWindow(openWindowAction: (() -> Void)? = nil) {
        guard let window = mainWindow() else {
            openMainWindow(openWindowAction: openWindowAction)
            return
        }

        if environment.isAppActive && window.isVisible {
            hideMainWindow()
            return
        }

        openMainWindow(openWindowAction: openWindowAction)
    }

    func handleMainWindowEscape(_ event: NSEvent) -> NSEvent? {
        guard isPlainEscape(event),
              let eventWindow = event.window,
              isMainWindow(eventWindow)
        else {
            return event
        }

        hideMainWindow()
        return nil
    }

    func mainWindow() -> NSWindow? {
        environment.windows.first(where: isMainWindow)
    }

    private func isMainWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), window.canBecomeMain else {
            return false
        }

        let controllerType = String(reflecting: type(of: window.contentViewController))
        if controllerType.contains("SettingsRootView") {
            return false
        }
        if controllerType.contains("RootView") {
            return true
        }

        // Fallback: the main app window has no toolbar; settings windows do.
        return window.toolbar == nil
    }
    private func isPlainEscape(_ event: NSEvent) -> Bool {
        guard event.keyCode == UInt16(kVK_Escape) else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.isEmpty
    }
}
