import AppKit

/// Adobe Fonts are turned on and off in Creative Cloud. Its app takes no links to its Fonts page, so this opens
/// the app, or Adobe Fonts' website without it.
enum CreativeCloud {
    static func open() {
        let workspace = NSWorkspace.shared
        if let app = workspace.urlForApplication(withBundleIdentifier: "com.adobe.acc.AdobeCreativeCloud") {
            workspace.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(URL(string: "https://fonts.adobe.com/")!)
        }
    }
}
