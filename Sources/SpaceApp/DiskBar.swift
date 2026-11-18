import SwiftUI
import SpaceCore

extension StorageSegment.Kind {
    var title: String {
        switch self {
        case .apps: return t("Apps")
        case .personal: return t("Documentos y archivos")
        case .appData: return t("Datos de apps y cachés")
        case .development: return t("Desarrollo")
        case .macOS: return "macOS"
        case .trash: return t("Papelera")
        case .purgeable: return t("Purgable por macOS")
        case .system: return t("Otros")
        }
    }
    var explanation: String {
        switch self {
        case .apps: return t("Aplicaciones, en /Applications y ~/Applications.")
        case .personal: return t("Tus carpetas: Documentos, Escritorio, Descargas, Imágenes, iCloud Drive…")
        case .appData: return t("La Biblioteca de tu carpeta personal: datos, configuración y cachés de las apps.")
        case .development: return t("Proyectos, SDK de Android, Xcode y simuladores, Homebrew, cachés de Gradle, npm, pnpm…")
        case .macOS: return t("El sistema, el arranque y la recuperación, la memoria virtual (intercambio) y los recursos que descarga macOS.")
        case .trash: return t("Se libera al vaciar la Papelera.")
        case .purgeable: return t("macOS lo libera por sí mismo cuando hace falta (cachés de iCloud, instantáneas locales…).")
        case .system: return t("Lo que no se puede atribuir: datos de apps que macOS protege (contenedores, Fotos, Mail…), carpetas sin permiso de lectura, otros usuarios, metadatos de APFS…")
        }
    }
}

/// Barra del disco: el total del volumen repartido por categorías, con el espacio disponible al final.
struct DiskBar: View {
    let capacity: VolumeCapacity?
    let storage: StorageBreakdown?
    let progress: (done: Int, total: Int)?
    let palette: Palette
    var compact = false
    var onMeasure: () -> Void = {}

    struct Piece: Identifiable {
        let id: String
        let title: String
        let bytes: Int64
        let color: Color
        let detail: String
        var isAvailable = false
    }

    var pieces: [Piece] {
        if let storage {
            return storage.segments.filter { $0.bytes > 0 }.map {
                Piece(id: $0.id, title: $0.kind.title, bytes: $0.bytes, color: palette.color($0.kind), detail: $0.kind.explanation + ($0.partial ? " " + t("Hubo elementos ilegibles: es un mínimo.") : ""))
            } + [Piece(id: "available", title: t("Disponible"), bytes: storage.available, color: .clear, detail: t("Espacio libre para tus archivos."), isAvailable: true)]
        }
        guard let capacity else { return [] }
        return [Piece(id: "used", title: t("Usado"), bytes: capacity.total - capacity.available, color: Color(hex: 0x6B7280), detail: t("Aún no se ha medido el desglose.")),
                Piece(id: "available", title: t("Disponible"), bytes: capacity.available, color: .clear, detail: t("Espacio libre para tus archivos."), isAvailable: true)]
    }

    var body: some View {
        let total = storage?.total ?? capacity?.total ?? 0
        let available = storage?.available ?? capacity?.available ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(t("%@ disponibles", size(available))).font(compact ? .headline : .title2.weight(.semibold)).monospacedDigit()
                Text(t("de %@", size(total))).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if let progress {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))).frame(width: 90)
                    Text(t("Midiendo el disco…")).font(.caption).foregroundStyle(.secondary)
                } else if !compact {
                    if let storage { Text(t("Medido %@", storage.date.formatted(.relative(presentation: .named).locale(Localizer.locale)))).font(.caption).foregroundStyle(.secondary) }
                    Button(storage == nil ? t("Medir el disco") : t("Volver a medir"), systemImage: "arrow.clockwise", action: onMeasure).controlSize(.small)
                }
            }
            bar(total: total).frame(height: compact ? 14 : 26)
            if !compact { legend(total: total) }
        }
        .accessibilityElement(children: .contain)
    }

    func bar(total: Int64) -> some View {
        GeometryReader { geo in
            HStack(spacing: palette.highContrast ? 2 : 1) {
                ForEach(pieces) { piece in
                    let width = max(piece.bytes > 0 ? 3 : 0, geo.size.width * CGFloat(Double(piece.bytes) / Double(max(total, 1))) - (palette.highContrast ? 2 : 1))
                    Group {
                        if piece.isAvailable {
                            Rectangle().fill(Color.primary.opacity(0.06))
                                .overlay(Rectangle().strokeBorder(Color.primary.opacity(palette.highContrast ? 0.6 : 0.2), lineWidth: palette.borderWidth))
                        } else {
                            Rectangle().fill(piece.color)
                        }
                    }
                    .frame(width: width)
                    .help("\(piece.title): \(size(piece.bytes)) (\(percent(piece.bytes, of: total))) · \(piece.detail)")
                    .accessibilityElement()
                    .accessibilityLabel("\(piece.title), \(size(piece.bytes)), \(percent(piece.bytes, of: total))")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(palette.highContrast ? 0.7 : 0.15), lineWidth: palette.borderWidth))
        }
    }

    func legend(total: Int64) -> some View {
        // Nombre arriba y cifras debajo: los nombres largos («Datos de apps y cachés») caben sin cortarse.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .topLeading)], alignment: .leading, spacing: 10) {
            ForEach(pieces) { piece in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Group {
                        if piece.isAvailable {
                            RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.5), lineWidth: 1)
                        } else {
                            RoundedRectangle(cornerRadius: 3).fill(piece.color)
                        }
                    }.frame(width: 11, height: 11).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(piece.title).font(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text("\(size(piece.bytes)) · \(percent(piece.bytes, of: total))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .help(piece.detail)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
