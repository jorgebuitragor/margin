import Foundation
import CoreGraphics

/// Mapa de áreas «squarified» (Bruls, Huizing y van Wijk, 2000): reparte un rectángulo en piezas proporcionales a los
/// valores, buscando que sean lo más cuadradas posible para que se puedan comparar a simple vista.
public enum Treemap {
    /// Devuelve un rectángulo por valor, en el mismo orden. Los valores deben venir ordenados de mayor a menor;
    /// los valores cero o negativos reciben un rectángulo vacío.
    public static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var rects = [CGRect](repeating: .zero, count: values.count)
        let indices = values.indices.filter { values[$0] > 0 }
        let total = indices.reduce(0) { $0 + values[$1] }
        guard total > 0, rect.width > 0, rect.height > 0 else { return rects }
        let scale = Double(rect.width * rect.height) / total
        let areas = indices.map { values[$0] * scale }
        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var rowSum = areas[start]
            var best = worst(areas[start..<end], sum: rowSum, side: side)
            while end < areas.count {
                let candidateSum = rowSum + areas[end]
                let candidate = worst(areas[start...end], sum: candidateSum, side: side)
                if candidate > best { break }
                rowSum = candidateSum
                best = candidate
                end += 1
            }
            if remaining.width >= remaining.height {
                // Columna a la izquierda: ancho = área de la fila / alto disponible.
                let width = CGFloat(rowSum / Double(remaining.height))
                var y = remaining.minY
                for k in start..<end {
                    let height = CGFloat(areas[k]) / width
                    rects[indices[k]] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY, width: max(0, remaining.width - width), height: remaining.height)
            } else {
                // Fila arriba: alto = área de la fila / ancho disponible.
                let height = CGFloat(rowSum / Double(remaining.width))
                var x = remaining.minX
                for k in start..<end {
                    let width = CGFloat(areas[k]) / height
                    rects[indices[k]] = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: max(0, remaining.height - height))
            }
            start = end
        }
        return rects
    }

    /// Peor proporción (lado largo / lado corto) de una fila con esas áreas sobre un lado de esa longitud.
    static func worst(_ row: ArraySlice<Double>, sum: Double, side: Double) -> Double {
        guard let largest = row.max(), let smallest = row.min(), sum > 0, smallest > 0 else { return .infinity }
        let s2 = sum * sum, w2 = side * side
        return max(w2 * largest / s2, s2 / (w2 * smallest))
    }

    /// Elementos de un nivel del mapa a partir del informe: subcarpetas directas de `parent` más un resto
    /// («archivos sueltos y carpetas pequeñas») para que las áreas sumen el total de la carpeta.
    public static func children(of parent: String, in report: ScanReport) -> [FolderTotal] {
        let canonicalParent = URL(fileURLWithPath: parent).standardizedFileURL.path
        guard let node = report.folders.first(where: { $0.path == canonicalParent }) else { return [] }
        var items = report.folders.filter {
            $0.depth == node.depth + 1 && URL(fileURLWithPath: $0.path).deletingLastPathComponent().standardizedFileURL.path == canonicalParent
        }.sorted { $0.allocatedBytes > $1.allocatedBytes }
        let rest = node.allocatedBytes - items.reduce(0) { $0 + $1.allocatedBytes }
        if rest > node.allocatedBytes / 100 {
            items.append(FolderTotal(path: canonicalParent + "/…", depth: node.depth + 1, allocatedBytes: rest, files: 0, partial: false, protection: nil, reason: "Archivos sueltos y carpetas por debajo del tamaño mínimo del informe."))
            items.sort { $0.allocatedBytes > $1.allocatedBytes }
        }
        return items
    }
}
