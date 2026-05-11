import Testing
import Foundation
@testable import ClaudeAgentsMonitor

@Suite("AgentLoader")
struct AgentLoaderTests {
    @Test("Parses frontmatter and body")
    func frontmatterParsing() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let agentFile = dir.appendingPathComponent("test.md")
        let content = """
        ---
        name: test
        description: Test agent
        model: sonnet
        tools: Read, Edit, Bash(git:*)
        ---

        Body text.

        ## Available skills
        - **simplify** — review code

        """
        try content.write(to: agentFile, atomically: true, encoding: .utf8)

        let agent = try #require(AgentLoader.parse(file: agentFile))
        #expect(agent.name == "test")
        #expect(agent.description == "Test agent")
        #expect(agent.model == "sonnet")
        #expect(agent.tools.count == 3)
        #expect(agent.tools.contains("Bash(git:*)"))
        #expect(agent.attachedSkills == ["simplify"])
    }

    @Test("Strips auto-injected blocks from prompt")
    func stripsInjectedBlocks() {
        let agent = Agent(
            id: "x", name: "x", description: "",
            tools: [], model: nil,
            systemPrompt: "Body text.\n\n## Memory protocol\nload memory.\n\n## Available skills\n- foo",
            attachedSkills: [],
            filePath: URL(fileURLWithPath: "/tmp/x.md"),
            memoryPath: nil
        )
        #expect(agent.promptWithoutInjectedBlocks == "Body text.")
    }
}
