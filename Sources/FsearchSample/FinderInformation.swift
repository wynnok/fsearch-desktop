import Carbon
import Foundation

@MainActor
enum FinderInformation {
    static func show(_ url: URL) throws {
        let script = NSAppleScript(source: """
        on showFileInfo(filePath)
            tell application "Finder"
                activate
                open information window of (POSIX file filePath as alias)
            end tell
        end showFileInfo
        """)
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
                                         eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil,
                                         returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "showFileInfo"), forKeyword: AEKeyword(keyASSubroutineName))
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: url.path), at: 1)
        event.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        guard script?.executeAppleEvent(event, error: &error) != nil else {
            throw NSError(domain: NSOSStatusErrorDomain, code: error?[NSAppleScript.errorNumber] as? Int ?? -1)
        }
    }
}
