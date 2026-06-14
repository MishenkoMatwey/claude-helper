import Foundation

/// Headless command-line entry points for the CAM binary. The same executable
/// serves as the GUI app, the MCP servers (`claude` launches it), and the
/// maintenance/test commands. If an argument matches, the command runs and the
/// process exits before any window is created.
enum CLI {
    private static let commands: [(flag: String, run: () -> Void)] = [
        // MCP servers (spawned by `claude` over stdio).
        ("--mcp-serve", MemoryMCPServer.run),
        ("--agents-serve", AgentMCPServer.run),
        // Maintenance.
        ("--migrate-all", MemoryMigration.migrateAllCLI),
        ("--rewire-all", AgentMaintenance.rewireAllCLI),
        ("--rewire-orchestrators", AgentMaintenance.rewireOrchestratorsCLI),
        // Tests.
        ("--selftest", SelfTest.runAll),
    ]

    /// Run the first matching command and exit; no-op (returns) for a normal GUI launch.
    static func runIfRequested() {
        let args = Set(CommandLine.arguments)
        guard let cmd = commands.first(where: { args.contains($0.flag) }) else { return }
        cmd.run()
        exit(0)
    }
}
