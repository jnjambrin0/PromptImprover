import Foundation

enum CLIExecutionEnvironment {
    static func patchedPATH(executableURL: URL, basePATH: String?) -> String {
        let executableDirectory = executableURL.deletingLastPathComponent().path
        let inheritedPATH = basePATH ?? ""
        return inheritedPATH.isEmpty ? executableDirectory : "\(executableDirectory):\(inheritedPATH)"
    }

    static func environmentForExecutable(
        executableURL: URL,
        baseEnv: [String: String]
    ) -> [String: String] {
        var environment = baseEnv
        environment["PATH"] = patchedPATH(executableURL: executableURL, basePATH: baseEnv["PATH"])
        return environment
    }
}
