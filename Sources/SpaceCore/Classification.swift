import Foundation

public enum Category: String, Codable, CaseIterable, Sendable {
    /// Solo lo asigna un perfil de desarrollo con una regla específica (ver Profiles/). Nunca el clasificador genérico.
    case lowRisk = "Candidato de bajo riesgo"
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
            return loc("Ubicación de sistema, configuración, aplicación o recuperación. Se mide su tamaño, pero sus archivos no se listan ni se ofrecen para limpieza.", "System, settings, application or recovery location. Its size is measured, but its files aren't listed or offered for cleanup.")
        }
        let temporaryRoot = parts.count >= 3 && parts[1] == "private" && parts[2] == "tmp"
        if parts.count > 1 && ["bin", "sbin", "usr", "etc", "private", "dev"].contains(parts[1]) && !temporaryRoot {
            return loc("Ubicación del sistema; no se analiza para limpieza.", "System location; not scanned for cleanup.")
        }
        if isPackage || ["app", "photoslibrary", "photolibrary", "backupbundle", "sparsebundle", "framework"].contains(url.pathExtension.lowercased()) {
            return loc("Paquete o biblioteca: puede contener una aplicación, fotos o una copia de seguridad. Se mide su tamaño, pero no se listan sus archivos.", "Package or library: it may contain an app, photos or a backup. Its size is measured, but its files aren't listed.")
        }
        if url.lastPathComponent.hasPrefix(".env") || ["key", "pem", "p12", "keychain", "keychain-db", "sqlite", "sqlite3", "db"].contains(url.pathExtension.lowercased()) {
            return loc("Puede contener credenciales, configuración o una base de datos necesaria.", "It may contain credentials, settings or a needed database.")
        }
        return nil
    }

    public static func synced(_ provider: String) -> Classification {
        Classification(category: .protected, reason: loc("Carpeta sincronizada con \(provider). Se mide su tamaño, pero sus archivos no se listan ni se ofrecen para limpieza.", "Folder synced with \(provider). Its size is measured, but its files aren't listed or offered for cleanup."), consequence: loc("Borrar aquí puede eliminar la copia en la nube y en tus otros dispositivos.", "Deleting here may remove the copy in the cloud and on your other devices."), rule: "sync")
    }

    public static func classify(_ url: URL, isPackage: Bool = false, isCloud: Bool = false, isLink: Bool = false) -> Classification {
        if isLink {
            return Classification(category: .unknown, reason: loc("Enlace o alias: el destino no se inspecciona.", "Link or alias: the target isn't inspected."), consequence: loc("No se conoce la función del destino.", "The target's purpose is unknown."), rule: "link")
        }
        if let reason = protectedReason(url, isPackage: isPackage) {
            return Classification(category: .protected, reason: reason, consequence: loc("Eliminarlo podría impedir funcionamiento o recuperación de datos.", "Removing it could break something or prevent data recovery."), rule: "protected")
        }
        if isCloud {
            return Classification(category: .protected, reason: loc("Archivo identificado como iCloud. No se descarga ni se lee su contenido.", "File identified as iCloud. Its contents aren't downloaded or read."), consequence: loc("Borrarlo puede afectar otros dispositivos sincronizados.", "Deleting it may affect other synced devices."), rule: "cloud")
        }
        let ext = url.pathExtension.lowercased()
        if ["dmg", "pkg", "zip", "tar", "gz", "7z"].contains(ext) {
            return Classification(category: .review, reason: loc("Parece un instalador o archivo comprimido por su extensión. No se ha comprobado su contenido ni si tienes otra copia.", "Looks like an installer or archive by its extension. Its contents weren't checked, nor whether you have another copy."), consequence: loc("Podrías perder material archivado o una versión necesaria para reinstalar.", "You could lose archived material or a version needed to reinstall."), rule: "archive")
        }
        if ["pdf", "txt", "md", "doc", "docx", "xls", "xlsx", "csv", "pptx", "jpg", "jpeg", "png", "heic", "mov", "mp4", "mp3", "wav"].contains(ext) {
            return Classification(category: .review, reason: loc("Posible archivo personal según su extensión. Su tamaño y antigüedad no demuestran que sobre.", "Possible personal file by its extension. Its size and age don't prove it's not needed."), consequence: loc("Podría ser tu única copia. Revísalo en Finder.", "It may be your only copy. Check it in Finder."), rule: "personal")
        }
        return Classification(category: .unknown, reason: loc("Los metadatos no bastan para establecer si es prescindible; llamarse caché o temporal no lo demuestra.", "Metadata isn't enough to tell whether it's disposable; being called cache or temp doesn't prove it."), consequence: loc("Conservar hasta conocer su función y dependencias.", "Keep it until its purpose and dependencies are known."), rule: "unknown")
    }
}
