import Foundation

/// Copies bundled helper scripts (Resources/AgentScripts/*.py) into a project's
/// `<agentsRoot>/scripts/` so template agents can call a tested CLI instead of
/// hand-rolling curl. Idempotent — overwrites with the shipped version each time.
enum AgentScriptInstaller {
    /// Relative path agents use to invoke a script from the project root.
    static func relativePath(_ filename: String) -> String { ".claude/agents/scripts/\(filename)" }

    /// Install the given bundled scripts into `agentsRoot/scripts/`. Returns the
    /// filenames that were successfully installed.
    @discardableResult
    static func install(_ filenames: [String], into agentsRoot: URL) -> [String] {
        guard !filenames.isEmpty else { return [] }
        let dest = agentsRoot.appendingPathComponent("scripts")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        var installed: [String] = []
        for name in filenames {
            guard let src = bundledURL(name) else { continue }
            let target = dest.appendingPathComponent(name)
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
                try FileManager.default.copyItem(at: src, to: target)
                // Make it executable (best-effort).
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: target.path)
                installed.append(name)
            } catch {
                continue
            }
        }
        return installed
    }

    /// Locate a bundled script. `.copy("Resources/AgentScripts")` preserves the
    /// directory, so the resource lives under the `AgentScripts` subdirectory.
    private static func bundledURL(_ filename: String) -> URL? {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        return Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "AgentScripts")
            ?? Bundle.module.url(forResource: base, withExtension: ext)
    }
}
