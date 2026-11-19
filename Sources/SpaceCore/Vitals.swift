import Foundation
import Darwin
import IOKit
import IOKit.ps

/// Rendimiento del Mac además de la memoria: CPU, estado térmico, batería y tiempo encendido. Solo lectura.
///
/// El uso de CPU sale de comparar dos muestras (como Monitor de Actividad): la primera lectura no tiene con qué
/// compararse y devuelve el uso desde la muestra anterior a partir de la segunda.
public struct SystemVitals: Sendable {
    /// Uso total de CPU entre la muestra anterior y esta, de 0 a 1. Nil en la primera muestra.
    public var cpuLoad: Double?
    public var cpuCount: Int
    /// Carga media de 1, 5 y 15 minutos (procesos que esperan CPU).
    public var loadAverage: [Double]
    public var thermal: Thermal
    public var uptime: TimeInterval?
    public var battery: Battery?
    /// Apps que más CPU usan entre las dos muestras (100 % = un núcleo entero).
    public var topCPU: [AppCPU]

    public enum Thermal: Int, Sendable {
        case nominal, fair, serious, critical
        init(_ state: ProcessInfo.ThermalState) {
            switch state {
            case .nominal: self = .nominal
            case .fair: self = .fair
            case .serious: self = .serious
            case .critical: self = .critical
            @unknown default: self = .nominal
            }
        }
    }
}

public struct AppCPU: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    /// Porcentaje de un núcleo (puede pasar de 100 con varios núcleos).
    public let percent: Double
    public let processes: Int
}

public struct Battery: Sendable {
    /// Carga actual, de 0 a 100.
    public let charge: Int?
    public let isCharging: Bool
    public let onPower: Bool
    public let cycleCount: Int?
    /// Capacidad máxima actual frente a la de fábrica, de 0 a 100 (lo que macOS llama «Capacidad máxima»).
    public let health: Int?
    public let condition: String?
}

/// Toma muestras de CPU y guarda la anterior para calcular el uso entre las dos. Se usa desde un solo hilo.
public final class VitalsSampler: @unchecked Sendable {
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastProcesses: [pid_t: UInt64] = [:]
    private var lastDate: Date?
    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public init() {}

    public func sample(topLimit: Int = 8) -> SystemVitals {
        let now = Date()
        let ticks = Self.cpuTicks()
        var load: Double?
        if let ticks, let last = lastTicks, ticks.total > last.total {
            load = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
        }
        lastTicks = ticks
        let processes = processTimes()
        var top: [AppCPU] = []
        if let lastDate {
            let wall = now.timeIntervalSince(lastDate) * 1_000_000_000
            var totals: [String: (ns: Double, count: Int)] = [:]
            for (pid, cpu) in processes {
                guard let before = lastProcesses[pid], cpu >= before, wall > 0 else { continue }
                let key = AppMemory.owner(pid)
                totals[key, default: (0, 0)].ns += Double(cpu - before)
                totals[key, default: (0, 0)].count += 1
            }
            top = totals.map { AppCPU(name: $0.key, percent: $0.value.ns / wall * 100, processes: $0.value.count) }
                .filter { $0.percent >= 0.5 }
                .sorted { $0.percent > $1.percent }
            top = Array(top.prefix(topLimit))
        }
        lastProcesses = processes
        lastDate = now
        var averages = [Double](repeating: 0, count: 3)
        let gotAverages = getloadavg(&averages, 3) == 3
        return SystemVitals(cpuLoad: load, cpuCount: ProcessInfo.processInfo.activeProcessorCount,
                            loadAverage: gotAverages ? averages : [], thermal: .init(ProcessInfo.processInfo.thermalState),
                            uptime: Self.uptime(), battery: Self.battery(), topCPU: top)
    }

    /// Tics de CPU acumulados de todos los núcleos: ocupados (usuario, sistema, nice) y totales.
    static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1), idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + idle + nice)
    }

    /// Tiempo de CPU acumulado por proceso, en nanosegundos (los que macOS deja inspeccionar).
    func processTimes() -> [pid_t: UInt64] {
        let capacity = Int(proc_listallpids(nil, 0)) * 2
        guard capacity > 0 else { return [:] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = pids.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size)) }
        var times: [pid_t: UInt64] = [:]
        for pid in pids.prefix(Int(max(count, 0))) where pid > 0 {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard status == 0 else { continue }
            // En Apple Silicon los tiempos vienen en unidades de mach_absolute_time: se pasan a nanosegundos.
            let ticks = info.ri_user_time + info.ri_system_time
            times[pid] = ticks * UInt64(timebase.numer) / UInt64(max(timebase.denom, 1))
        }
        return times
    }

    static func uptime() -> TimeInterval? {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0, boot.tv_sec > 0 else { return nil }
        return Date().timeIntervalSince1970 - TimeInterval(boot.tv_sec)
    }

    /// Batería según IOKit (AppleSmartBattery). Nil en Macs de escritorio.
    static func battery() -> Battery? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        func int(_ key: String) -> Int? { (props[key] as? NSNumber)?.intValue }
        let design = int("DesignCapacity")
        let rawMax = int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity")
        let health = design.flatMap { d in rawMax.map { min(100, Int((Double($0) / Double(max(d, 1)) * 100).rounded())) } }
        // La carga en %, como la muestra macOS (en Apple Silicon «CurrentCapacity» ya es un porcentaje).
        var charge: Int?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                if let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                   let current = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                    charge = Int((Double(current) / Double(max) * 100).rounded())
                }
            }
        }
        // Algunos Macs de escritorio exponen el servicio vacío: sin capacidad de fábrica ni carga no hay batería.
        guard design != nil || charge != nil else { return nil }
        return Battery(charge: charge, isCharging: props["IsCharging"] as? Bool ?? false, onPower: props["ExternalConnected"] as? Bool ?? false,
                       cycleCount: int("CycleCount"), health: health, condition: props["BatteryHealthCondition"] as? String)
    }
}
