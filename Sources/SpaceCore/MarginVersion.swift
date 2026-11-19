import Foundation

/// Versión de Margin («0.10.0»), la del Info.plist de la app. La CLI vive dentro de la app
/// (Margin.app/Contents/Helpers/margin), así que la lee del Info.plist de la app que la contiene; compilada suelta
/// (swift run, pruebas) es «dev».
public enum MarginVersion {
    public static let current: String = {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { return version }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let plist = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        if let info = NSDictionary(contentsOf: plist), let version = info["CFBundleShortVersionString"] as? String { return version }
        return "dev"
    }()
}
