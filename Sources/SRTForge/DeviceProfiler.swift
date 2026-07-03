import Foundation
import Darwin

enum DeviceProfiler {
    static func current() -> DeviceProfile {
        let processInfo = ProcessInfo.processInfo
        let memoryGB = max(1, Int((processInfo.physicalMemory + 1_073_741_823) / 1_073_741_824))
        let activeCores = processInfo.activeProcessorCount
        let cpuCores = processInfo.processorCount
        let processorName = sysctlString("machdep.cpu.brand_string") ?? "Mac processor"
        let os = processInfo.operatingSystemVersion
        let osVersion = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"

        let parallelJobs: Int
        let tier: String
        let recommendation: String

        if memoryGB >= 48 && activeCores >= 10 {
            parallelJobs = 3
            tier = "Labai galingas"
            recommendation = "Gali vienu metu apdoroti kelis failus. Rekomenduojama iki 3 paralelinių SRT darbų su large-v3."
        } else if memoryGB >= 24 && activeCores >= 8 {
            parallelJobs = 2
            tier = "Galingas"
            recommendation = "Gali apdoroti 2 failus vienu metu. Jei failai labai ilgi, saugiau rinktis 1."
        } else {
            parallelJobs = 1
            tier = "Saugus režimas"
            recommendation = "Rekomenduojamas 1 failas vienu metu. Taip mažiau rizikos pritrūkti RAM su large-v3."
        }

        let recommendedThreads = max(2, min(8, activeCores / max(1, parallelJobs)))

        return DeviceProfile(
            processorName: processorName,
            cpuCores: cpuCores,
            activeCores: activeCores,
            memoryGB: memoryGB,
            osVersion: osVersion,
            tier: tier,
            recommendedParallelJobs: parallelJobs,
            recommendedThreadsPerJob: recommendedThreads,
            recommendation: recommendation
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
