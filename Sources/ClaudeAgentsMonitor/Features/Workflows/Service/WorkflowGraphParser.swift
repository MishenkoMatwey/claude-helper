import Foundation

/// Parses a markdown step list (produced by `WorkflowGraph.toMarkdownSteps`) back into a graph.
///
/// Recognised headers:
/// - `### Start — <id>`
/// - `### End — <id>` or `### End — <id> (<label>)`
/// - `### Step <N> — <agent-name>` or `### Step <N> — <agent-name> [id=<node-id>]`
/// - `### Gateway — <label>` or `### Gateway — <label> [id=<node-id>]`
/// - `### Parallel — <label>` or `### Parallel — <label> [id=<node-id>]`
///
/// Between agent header and the next `###` — body becomes the agent prompt. A leading
/// `**Prompt:**` line is stripped if present.
///
/// Between gateway header and next `###` — bullet lines of the form
/// `- if \`<condition>\` → <target-id-or-label>` define outgoing edges.
///
/// Sequential edges (`always`) are inferred between consecutive non-branching nodes.
enum WorkflowGraphParser {

    static func parse(markdown: String) -> WorkflowGraph? {
        let blocks = splitIntoBlocks(markdown)
        guard !blocks.isEmpty else { return nil }

        var nodes: [WorkflowNode] = []
        var edges: [WorkflowEdge] = []
        var pendingEdgesFromGateway: [(String, [(String, String)])] = []
        // For sequential linking: track id of the previous block that should flow to the next.
        var prevSequentialId: String? = nil

        for block in blocks {
            guard let header = block.header else { continue }
            let parsed = parseHeader(header)
            switch parsed.kind {
            case .start:
                let id = parsed.id ?? "start"
                nodes.append(WorkflowNode(
                    id: id, kind: .start, x: 0, y: 0,
                    label: "Start", prompt: "", priority: 0
                ))
                prevSequentialId = id
            case .end:
                let id = parsed.id ?? "end_\(nodes.count)"
                let label = parsed.label ?? "End"
                nodes.append(WorkflowNode(
                    id: id, kind: .end, x: 0, y: 0,
                    label: label, prompt: "", priority: 0
                ))
                // ends absorb a sequential edge from prev but don't continue.
                if let prev = prevSequentialId, prev != id {
                    edges.append(WorkflowEdge(id: "\(prev)__\(id)", from: prev, to: id, condition: "always"))
                }
                prevSequentialId = nil
            case .agent:
                let agentName = parsed.label ?? "agent"
                let id = parsed.id ?? slugify(agentName) + "_\(nodes.count)"
                let prompt = extractPrompt(block.body)
                nodes.append(WorkflowNode(
                    id: id, kind: .agent, x: 0, y: 0,
                    label: agentName, prompt: prompt, priority: 0
                ))
                if let prev = prevSequentialId, prev != id {
                    edges.append(WorkflowEdge(id: "\(prev)__\(id)", from: prev, to: id, condition: "always"))
                }
                prevSequentialId = id
            case .gateway:
                let label = parsed.label ?? "decision"
                let id = parsed.id ?? "gateway_\(nodes.count)"
                nodes.append(WorkflowNode(
                    id: id, kind: .gateway, x: 0, y: 0,
                    label: label, prompt: "", priority: 0
                ))
                if let prev = prevSequentialId, prev != id {
                    edges.append(WorkflowEdge(id: "\(prev)__\(id)", from: prev, to: id, condition: "always"))
                }
                let branches = parseGatewayBranches(block.body)
                pendingEdgesFromGateway.append((id, branches))
                // Gateway doesn't flow sequentially; its branches are explicit.
                prevSequentialId = nil
            case .parallel:
                let label = parsed.label ?? "parallel"
                let id = parsed.id ?? "parallel_\(nodes.count)"
                nodes.append(WorkflowNode(
                    id: id, kind: .parallel, x: 0, y: 0,
                    label: label, prompt: "", priority: 0
                ))
                if let prev = prevSequentialId, prev != id {
                    edges.append(WorkflowEdge(id: "\(prev)__\(id)", from: prev, to: id, condition: "always"))
                }
                let branches = parseParallelBranches(block.body)
                for (target, _) in branches {
                    let resolved = resolveTarget(target, in: nodes)
                    edges.append(WorkflowEdge(
                        id: "\(id)__\(resolved)__always",
                        from: id, to: resolved, condition: "always"
                    ))
                }
                prevSequentialId = nil
            case .unknown:
                continue
            }
        }

        // Resolve gateway branches now that all nodes are known.
        for (gatewayId, branches) in pendingEdgesFromGateway {
            for (condition, target) in branches {
                let resolved = resolveTarget(target, in: nodes)
                edges.append(WorkflowEdge(
                    id: "\(gatewayId)__\(resolved)__\(condition)",
                    from: gatewayId, to: resolved, condition: condition
                ))
            }
        }

        guard !nodes.isEmpty else { return nil }

        // Auto-layout: column-based by topological depth from start.
        layout(nodes: &nodes, edges: edges)

        return WorkflowGraph(nodes: nodes, edges: edges)
    }

    // MARK: - Header parsing

    private enum HeaderKind { case start, end, agent, gateway, parallel, unknown }

    private struct ParsedHeader {
        let kind: HeaderKind
        let label: String?
        let id: String?
    }

    private static func parseHeader(_ line: String) -> ParsedHeader {
        // strip leading "### " or "## "
        var text = line
        while text.hasPrefix("#") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespaces)

        // Extract optional [id=<value>] suffix
        var id: String? = nil
        if let r = text.range(of: #"\s*\[id=([A-Za-z0-9_\-]+)\]\s*$"#, options: .regularExpression) {
            let match = String(text[r])
            if let idr = match.range(of: #"id=([A-Za-z0-9_\-]+)"#, options: .regularExpression) {
                let kv = String(match[idr]).dropFirst(3) // drop "id="
                id = String(kv)
            }
            text.removeSubrange(r)
            text = text.trimmingCharacters(in: .whitespaces)
        }

        // Identify kind by leading keyword.
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        let keyword = parts.first?.lowercased() ?? ""
        var label: String? = nil

        switch keyword {
        case "start":
            // "Start" or "Start — <id-or-label>"
            label = extractAfterDash(text) ?? id
            return ParsedHeader(kind: .start, label: label, id: id ?? extractAfterDash(text))
        case "end":
            // "End — <id>" or "End — <id> (<label>)"
            let rest = extractAfterDash(text) ?? ""
            if let parenRange = rest.range(of: #"\(([^)]+)\)$"#, options: .regularExpression) {
                let inner = String(rest[parenRange]).dropFirst().dropLast()
                label = String(inner)
                let idPart = rest[..<parenRange.lowerBound].trimmingCharacters(in: .whitespaces)
                let resolvedId = id ?? (idPart.isEmpty ? nil : idPart)
                return ParsedHeader(kind: .end, label: label, id: resolvedId)
            }
            return ParsedHeader(kind: .end, label: rest.isEmpty ? nil : rest, id: id ?? (rest.isEmpty ? nil : rest))
        case "step":
            // "Step N — <agent>"
            let rest = extractAfterDash(text) ?? ""
            label = rest.isEmpty ? nil : rest
            return ParsedHeader(kind: .agent, label: label, id: id)
        case "gateway":
            label = extractAfterDash(text)
            return ParsedHeader(kind: .gateway, label: label, id: id)
        case "parallel":
            label = extractAfterDash(text)
            return ParsedHeader(kind: .parallel, label: label, id: id)
        default:
            return ParsedHeader(kind: .unknown, label: nil, id: nil)
        }
    }

    private static func extractAfterDash(_ s: String) -> String? {
        // Match em-dash, en-dash, or hyphen surrounded by spaces.
        if let r = s.range(of: #"\s+[—–-]\s+"#, options: .regularExpression) {
            return String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: - Body parsing

    private static func extractPrompt(_ body: String) -> String {
        var text = body
        // Strip optional **Prompt:** marker.
        if let r = text.range(of: #"^\s*\*\*Prompt:\*\*\s*\n?"#, options: .regularExpression) {
            text.removeSubrange(r)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lines like: `- if \`<condition>\` → <target>`
    private static func parseGatewayBranches(_ body: String) -> [(String, String)] {
        var out: [(String, String)] = []
        for raw in body.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("-") else { continue }
            // Match: `if \`<cond>\` → <target>` or `if <cond> -> <target>`
            let pattern = #"if\s+`?([^`→\->]+?)`?\s*(?:→|->)\s*([^\s]+)"#
            if let r = line.range(of: pattern, options: .regularExpression) {
                let match = String(line[r])
                let regex = try? NSRegularExpression(pattern: pattern)
                let ns = match as NSString
                if let m = regex?.firstMatch(in: match, range: NSRange(location: 0, length: ns.length)) {
                    let cond = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    let target = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
                    out.append((cond, target))
                }
            }
        }
        return out
    }

    /// Lines like: `- <target> (priority <N>)` or just `- <target>`
    private static func parseParallelBranches(_ body: String) -> [(String, Int)] {
        var out: [(String, Int)] = []
        for raw in body.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("-") else { continue }
            let stripped = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            // Match `<target> (priority <N>)`
            if let r = stripped.range(of: #"\s*\(priority\s+(\d+)\)\s*$"#, options: .regularExpression) {
                let match = String(stripped[r])
                let target = stripped[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let prio = Int(match.replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)) ?? 0
                out.append((target, prio))
            } else if !stripped.isEmpty {
                out.append((stripped, 0))
            }
        }
        return out
    }

    // MARK: - Target resolution

    private static func resolveTarget(_ target: String, in nodes: [WorkflowNode]) -> String {
        // Prefer exact id match; otherwise match by label.
        if nodes.contains(where: { $0.id == target }) { return target }
        if let byLabel = nodes.first(where: { $0.label == target }) { return byLabel.id }
        return target  // best-effort; validator will flag missing.
    }

    // MARK: - Block splitting

    private struct Block {
        var header: String?
        var body: String
    }

    private static func splitIntoBlocks(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var current = Block(header: nil, body: "")
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("### ") {
                if current.header != nil || !current.body.isEmpty {
                    blocks.append(current)
                }
                current = Block(header: s, body: "")
            } else {
                if !current.body.isEmpty { current.body += "\n" }
                current.body += s
            }
        }
        if current.header != nil { blocks.append(current) }
        return blocks
    }

    // MARK: - Layout

    private static func layout(nodes: inout [WorkflowNode], edges: [WorkflowEdge]) {
        let colWidth: Double = 220
        let rowHeight: Double = 140
        let baseY: Double = 240

        // Depth from start via BFS.
        var depth: [String: Int] = [:]
        let starts = nodes.filter { $0.kind == .start }.map(\.id)
        var queue: [(String, Int)] = starts.map { ($0, 0) }
        if queue.isEmpty, let first = nodes.first { queue = [(first.id, 0)] }

        while let (id, d) = queue.first {
            queue.removeFirst()
            if let existing = depth[id], existing <= d { continue }
            depth[id] = d
            for e in edges where e.from == id {
                queue.append((e.to, d + 1))
            }
        }
        // Disconnected nodes get the max depth + 1.
        let maxDepth = depth.values.max() ?? 0
        for n in nodes where depth[n.id] == nil {
            depth[n.id] = maxDepth + 1
        }

        // Group nodes by depth.
        var byDepth: [Int: [String]] = [:]
        for (id, d) in depth { byDepth[d, default: []].append(id) }

        for (d, ids) in byDepth {
            let sorted = ids.sorted()
            let count = sorted.count
            let startOffset = -Double(count - 1) * rowHeight / 2.0
            for (idx, id) in sorted.enumerated() {
                let y = baseY + startOffset + Double(idx) * rowHeight
                let x = 80.0 + Double(d) * colWidth
                if let i = nodes.firstIndex(where: { $0.id == id }) {
                    nodes[i].x = x
                    nodes[i].y = y
                }
            }
        }
    }

    private static func slugify(_ s: String) -> String {
        let lower = s.lowercased()
        var result = ""
        for ch in lower {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                result.append(ch)
            } else if ch == " " {
                result.append("_")
            }
        }
        return result.isEmpty ? "node" : result
    }
}
