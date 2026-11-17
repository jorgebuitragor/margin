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
    public private(set) var source = "ProcessInfo, host_statistics64, sysctl vm.swapusage, URLResourceValues"

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
        return Diagnostics(date: Date(), physicalMemory: ProcessInfo.processInfo.physicalMemory,
                           wiredMemory: valid ? UInt64(vm.wire_count) * UInt64(pageSize) : nil,
                           compressedMemory: valid ? UInt64(vm.compressor_page_count) * UInt64(pageSize) : nil,
                           swapUsed: swapResult == 0 ? swap.xsu_used : nil,
                           diskTotal: total, diskAvailable: available, errors: errors)
    }
}
