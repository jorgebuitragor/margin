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
        case .swap: return t("Intercambio (swap)")
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
        case .macOS: return t("El sistema, el arranque y la recuperación, y los recursos que descarga macOS.")
        case .swap: return t("Memoria que macOS pasa al disco cuando la RAM no alcanza. No se borra a mano: baja sola al cerrar apps que usan mucha memoria y se vacía al reiniciar. Más detalles en Rendimiento.")
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
    var reduceMotion = false
    var onMeasure: () -> Void = {}
    /// Clic en el tramo o en la leyenda de la Papelera: pide confirmación para vaciarla.
    var onEmptyTrash: (() -> Void)? = nil
    /// Las categorías se llenan de izquierda a derecha al aparecer.
    @State private var grown = false
    @State private var hovered: String?

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(size(available)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(t("disponibles de %@", size(total))).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if let progress {
                    Text(t("Midiendo el disco…")).font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))).frame(width: 90)
                } else if let storage {
                    Text(t("Medido %@", storage.date.formatted(.relative(presentation: .named).locale(Localizer.locale)))).font(.caption).foregroundStyle(.secondary)
                } else {
                    Button(t("Medir el disco"), systemImage: "arrow.clockwise", action: onMeasure).buttonStyle(.glass)
                }
            }
            .animation(.smooth, value: available)
            bar(total: total).frame(height: 30)
            legend(total: total)
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            if reduceMotion { grown = true } else { withAnimation(.spring(response: 0.9, dampingFraction: 0.82).delay(0.15)) { grown = true } }
        }
    }

    func bar(total: Int64) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = palette.highContrast ? 2 : 1.5
            let used = pieces.filter { !$0.isAvailable }
            let widths = used.map { max(3, geo.size.width * CGFloat(Double($0.bytes) / Double(max(total, 1))) - gap) * (grown ? 1 : 0) }
            HStack(spacing: gap) {
                ForEach(Array(used.enumerated()), id: \.element.id) { index, piece in
                    Rectangle().fill(piece.color.gradient)
                        .brightness(hovered == piece.id ? 0.12 : 0)
                        .frame(width: widths[index])
                        .onHover { hovered = $0 ? piece.id : (hovered == piece.id ? nil : hovered) }
                        .onTapGesture { if piece.id == StorageSegment.Kind.trash.rawValue { onEmptyTrash?() } }
                        .help("\(piece.title): \(size(piece.bytes)) (\(percent(piece.bytes, of: total))) · \(piece.detail)" + (piece.id == StorageSegment.Kind.trash.rawValue && onEmptyTrash != nil ? " " + t("Haz clic para vaciarla.") : ""))
                        .accessibilityElement()
                        .accessibilityLabel("\(piece.title), \(size(piece.bytes)), \(percent(piece.bytes, of: total))")
                }
                // Disponible: el hueco libre de la barra, con un borde punteado como el icono de Margin.
                if let free = pieces.first(where: \.isAvailable) {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(palette.highContrast ? 0.6 : 0.3), style: StrokeStyle(lineWidth: palette.borderWidth, dash: [4, 3]))
                        .padding(2)
                        .frame(maxWidth: .infinity)
                        .help("\(free.title): \(size(free.bytes)) (\(percent(free.bytes, of: total))) · \(free.detail)")
                        .accessibilityElement()
                        .accessibilityLabel("\(free.title), \(size(free.bytes)), \(percent(free.bytes, of: total))")
                }
            }
            .animation(.spring(response: 0.7, dampingFraction: 0.85), value: widths)
            .overlay { if progress != nil && !reduceMotion { Shimmer() } }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(palette.highContrast ? 0.7 : 0.12), lineWidth: palette.borderWidth))
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
                        if piece.id == StorageSegment.Kind.trash.rawValue, let onEmptyTrash {
                            Button(t("Vaciar…"), action: onEmptyTrash).buttonStyle(.link).font(.caption)
                        }
                    }
                }
                .help(piece.detail)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Brillo que recorre la barra mientras se mide el disco.
struct Shimmer: View {
    @State private var phase: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.35)
                .offset(x: phase * geo.size.width * 1.35)
                .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 } }
        }
        .allowsHitTesting(false)
        .blendMode(.plusLighter)
    }
}
