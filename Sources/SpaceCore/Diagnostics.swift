import Foundation
import Darwin

public struct Diagnostics: Codable, Sendable {
    public let date: Date
    public let physicalMemory: UInt64
    public let wiredMemory: UInt64?
    public let compressedMemory: UInt64?
    public let swapUsed: UInt64?
    public let diskTotal: Int64?
    public let diskAvailable: Int64?
    public let errors: [String]
    public private(set) var source = "ProcessInfo, host_statistics64, sysctl vm.swapusage y kern.memorystatus_vm_pressure_level, proc_pid_rusage, URLResourceValues"
    /// Presión de memoria según macOS: 1 normal, 2 advertencia, 4 crítica (la misma señal que el gráfico de Monitor de Actividad).
    public var pressureLevel: Int? = nil
    /// Memoria por app (huella física, como la columna «Memoria» de Monitor de Actividad), sumando sus procesos auxiliares.
    public var apps: [AppMemory] = []
    /// Procesos que macOS no deja inspeccionar sin privilegios (del sistema u otros usuarios).
    public var hiddenProcesses = 0

    public var pressure: String? {
        switch pressureLevel {
        case 1?: return "Normal"
        case 2?: return "Advertencia"
        case 4?: return "Crítica"
        default: return nil
        }
    }

    public static func read() -> Diagnostics {
        var errors: [String] = []
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        let valid = result == KERN_SUCCESS && pageResult == KERN_SUCCESS
        if !valid { errors.append("Estadísticas de memoria no disponibles (\(result)).") }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        let swapResult = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        if swapResult != 0 { errors.append("Intercambio no disponible.") }
        var total: Int64?
        var available: Int64?
        do {
            let values = try FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
            total = values.volumeTotalCapacity.map(Int64.init)
            available = values.volumeAvailableCapacity.map(Int64.init)
        } catch { errors.append("Capacidad del volumen no disponible: \(error.localizedDescription)") }
        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        let pressureLevel = sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 ? Int(level) : nil
        if pressureLevel == nil { errors.append("Presión de memoria no disponible.") }
        let (apps, hidden) = AppMemory.top(limit: 12)
        var diagnostics = Diagnostics(date: Date(), physicalMemory: ProcessInfo.processInfo.physicalMemory,
                           wiredMemory: valid ? UInt64(vm.wire_count) * UInt64(pageSize) : nil,
                           compressedMemory: valid ? UInt64(vm.compressor_page_count) * UInt64(pageSize) : nil,
                           swapUsed: swapResult == 0 ? swap.xsu_used : nil,
                           diskTotal: total, diskAvailable: available, errors: errors)
        diagnostics.pressureLevel = pressureLevel
        diagnostics.apps = apps
        diagnostics.hiddenProcesses = hidden
        return diagnostics
    }
}

public struct AppMemory: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let bytes: UInt64
    public let processes: Int

    /// Agrupa por la app (.app) que contiene cada proceso; los procesos sueltos van por su nombre. Solo lectura.
    public static func top(limit: Int) -> ([AppMemory], Int) {
        let capacity = Int(proc_listallpids(nil, 0)) * 2
        guard capacity > 0 else { return ([], 0) }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size)) }
        var totals: [String: (bytes: UInt64, processes: Int)] = [:]
        var hidden = 0
        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard status == 0 else { hidden += 1; continue }
            let key = owner(pid)
            totals[key, default: (0, 0)].bytes += info.ri_phys_footprint
            totals[key, default: (0, 0)].processes += 1
        }
        let apps = totals.map { AppMemory(name: $0.key, bytes: $0.value.bytes, processes: $0.value.processes) }
            .sorted { $0.bytes > $1.bytes }
        return (Array(apps.prefix(limit)), hidden)
    }

    static func owner(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = String(cString: buffer)
            // La primera .app del camino es la app principal (los auxiliares viven dentro de ella).
            if let range = path.range(of: ".app/") {
                return URL(fileURLWithPath: String(path[..<range.lowerBound])).lastPathComponent
            }
            return URL(fileURLWithPath: path).lastPathComponent
        }
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, 256)
        return String(cString: name)
    }
}
