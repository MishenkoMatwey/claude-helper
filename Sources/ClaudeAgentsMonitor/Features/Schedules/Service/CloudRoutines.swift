import Foundation

/// Wrapper around the built-in `/schedule` skill which manages Anthropic Routines (cloud).
/// We invoke `claude --print` with structured natural language commands and parse the response.
/// This is simpler than reverse-engineering the Routines API.
enum CloudRoutines {
    static func createCommand(name: String, cron: String, target: String, prompt: String) -> String {
        // Use the /schedule skill: it understands prose like this.
        """
        /schedule create a cloud routine named "\(name)" that runs on cron "\(cron)" \
        and invokes the agent "\(target)" with this prompt:
        \"\"\"
        \(prompt)
        \"\"\"
        """
    }

    static func listCommand() -> String {
        "/schedule list all my cloud routines as JSON"
    }

    static func deleteCommand(routineId: String) -> String {
        "/schedule delete routine with id \(routineId)"
    }

    /// Open a Claude session prefilled with the given /schedule command via the Terminal.
    /// (We don't auto-execute because /schedule may need confirmation and routine quotas
    /// belong to the user; manual invocation is safer.)
    static func clipboardCommand(_ text: String) -> String {
        // Wrap so the user can paste into a terminal that already has `claude` open.
        text
    }
}
