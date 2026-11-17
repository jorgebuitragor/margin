import Foundation

public enum Category: String, Codable, CaseIterable, Sendable {
    case review = "Revisar antes de borrar"
    case protected = "Conservar / protegido"
    case unknown = "No determinado"
}

public struct Classification: Codable, Sendable {
    public let category: Category
    public let reason: String
    public let consequence: String
    public let rule: String
    public private(set) var ruleVersion = 1
    public private(set) var canDelete = false // La primera entrega no expone operaciones de escritura.
}

public enum Classifier {
    public static func protectedReason(_ url: URL, isPackage: Bool = false) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        let reserved: Set<String> = ["System", "Library", "Applications", ".ssh", ".gnupg", ".git", ".aws", ".config", ".Trash", ".build", "node_modules", "Backups.backupdb"]
        if parts.contains(where: { reserved.contains($0) }) {
            return "Ubicación de sistema, configuración, aplicación o recuperación. Se mide su tamaño, pero sus archivos no se listan ni se ofrecen para limpieza."
        }
        let temporaryRoot = parts.count >= 3 && parts[1] == "private" && parts[2] == "tmp"
        if parts.count > 1 && ["bin", "sbin", "usr", "etc", "private", "dev"].contains(parts[1]) && !temporaryRoot {
            return "Ubicación del sistema; no se analiza para limpieza."
        }
        if isPackage || ["app", "photoslibrary", "photolibrary", "backupbundle", "sparsebundle", "framework"].contains(url.pathExtension.lowercased()) {
            return "Paquete o biblioteca: puede contener una aplicación, fotos o una copia de seguridad. Se mide su tamaño, pero no se listan sus archivos."
        }
        if url.lastPathComponent.hasPrefix(".env") || ["key", "pem", "p12", "keychain", "keychain-db", "sqlite", "sqlite3", "db"].contains(url.pathExtension.lowercased()) {
            return "Puede contener credenciales, configuración o una base de datos necesaria."
        }
        return nil
    }

    public static func synced(_ provider: String) -> Classification {
        Classification(category: .protected, reason: "Carpeta sincronizada con \(provider). Se mide su tamaño, pero sus archivos no se listan ni se ofrecen para limpieza.", consequence: "Borrar aquí puede eliminar la copia en la nube y en tus otros dispositivos.", rule: "sync")
    }

    public static func classify(_ url: URL, isPackage: Bool = false, isCloud: Bool = false, isLink: Bool = false) -> Classification {
        if isLink {
            return Classification(category: .unknown, reason: "Enlace o alias: el destino no se inspecciona.", consequence: "No se conoce la función del destino.", rule: "link")
        }
        if let reason = protectedReason(url, isPackage: isPackage) {
            return Classification(category: .protected, reason: reason, consequence: "Eliminarlo podría impedir funcionamiento o recuperación de datos.", rule: "protected")
        }
        if isCloud {
            return Classification(category: .protected, reason: "Archivo identificado como iCloud. No se descarga ni se lee su contenido.", consequence: "Borrarlo puede afectar otros dispositivos sincronizados.", rule: "cloud")
        }
        let ext = url.pathExtension.lowercased()
        if ["dmg", "pkg", "zip", "tar", "gz", "7z"].contains(ext) {
            return Classification(category: .review, reason: "Parece un instalador o archivo comprimido por su extensión. No se ha comprobado su contenido ni si tienes otra copia.", consequence: "Podrías perder material archivado o una versión necesaria para reinstalar.", rule: "archive")
        }
        if ["pdf", "txt", "md", "doc", "docx", "xls", "xlsx", "csv", "pptx", "jpg", "jpeg", "png", "heic", "mov", "mp4", "mp3", "wav"].contains(ext) {
            return Classification(category: .review, reason: "Posible archivo personal según su extensión. Su tamaño y antigüedad no demuestran que sobre.", consequence: "Podría ser tu única copia. Revísalo en Finder.", rule: "personal")
        }
        return Classification(category: .unknown, reason: "Los metadatos no bastan para establecer si es prescindible; llamarse caché o temporal no lo demuestra.", consequence: "Conservar hasta conocer su función y dependencias.", rule: "unknown")
    }
}
