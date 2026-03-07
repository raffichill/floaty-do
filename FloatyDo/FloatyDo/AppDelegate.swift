import Cocoa
import FloatyDoLib

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let implementation = FloatyDoLib.AppDelegate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        implementation.applicationDidFinishLaunching(notification)
    }

    func applicationWillTerminate(_ notification: Notification) {}

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
