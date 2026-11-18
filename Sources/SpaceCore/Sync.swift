import Foundation

/// Detecta carpetas sincronizadas con un servicio en la nube. Todo lo que detecta queda protegido:
/// borrar ahí puede afectar a otros dispositivos o a la copia en la nube.
public enum SyncDetector {
    /// Marcadores que el proveedor deja en la raíz de una carpeta sincronizada.
    static let markers: [(name: String, provider: String)] = [
        (".tmp.driveupload", "Google Drive"),
        (".tmp.drivedownload", "Google Drive"),
        (".dropbox", "Dropbox"),
        (".dropbox.cache", "Dropbox")
    ]

    /// Proveedor que sincroniza esta carpeta, si se reconoce. Solo mira metadatos: nunca descarga ni lee contenido.
    public static func provider(forDirectory url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        if let index = parts.firstIndex(of: "Library"), index + 1 < parts.count {
            switch parts[index + 1] {
            case "CloudStorage":
                if index + 2 < parts.count { return providerName(fromCloudStorage: parts[index + 2]) }
                return loc("Proveedor de archivos (CloudStorage)", "File provider (CloudStorage)")
            case "Mobile Documents": return "iCloud Drive"
            default: break
            }
        }
        let fm = FileManager.default
        for marker in markers where fm.fileExists(atPath: url.appendingPathComponent(marker.name).path) {
            return marker.provider
        }
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true { return "iCloud Drive" }
        return nil
    }

    /// Busca el proveedor en la carpeta o en cualquiera de sus antecesoras (por ejemplo, una subcarpeta de Documentos
    /// cuando Documentos se refleja en Google Drive).
    public static func provider(forDirectoryOrAncestors url: URL) -> (provider: String, root: String)? {
        var current = url.standardizedFileURL
        while true {
            if let provider = provider(forDirectory: current) { return (provider, current.path) }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path || current.path == "/" { return nil }
            current = parent
        }
    }

    static func providerName(fromCloudStorage folder: String) -> String {
        let known = ["GoogleDrive": "Google Drive", "OneDrive": "OneDrive", "Dropbox": "Dropbox", "Box": "Box"]
        for (prefix, name) in known where folder.hasPrefix(prefix) { return name }
        return loc("Proveedor de archivos (\(folder))", "File provider (\(folder))")
    }
}
