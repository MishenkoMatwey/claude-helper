import Foundation
import SwiftUI

struct AgentTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String                // SF Symbol fallback
    let assetIcon: String?          // Bundled PNG name in Resources/BrandIcons (without extension)
    let color: String          // Hex or DS color key
    let description: String
    let model: String          // "sonnet" / "opus" / "haiku" / "default"
    let suggestedTools: [CommonTool]
    let bashPresetIds: [String]    // labels matching BashPresets.label
    let bashCategories: [String]   // filter quick presets to only these categories (empty = show all)
    let suggestedSkillNames: [String]
    let suggestedPluginIds: [String]   // plugin id like "code-review@claude-plugins-official"
    let secretsToSetup: [SecretField]
    let plainVarsToSetup: [PlainVarField]
    let promptTemplate: String
    let validation: TemplateValidation?
    /// Optional list of grouped "connection" blocks. Each block has its own Verify button.
    /// When non-empty, the template sheet renders a dedicated Connections section in place of
    /// generic plain-vars/secrets for these fields (other vars/secrets still render normally).
    var connections: [ConnectionField] = []
    /// Shell command run AFTER the agent has been saved (with vars/secrets persisted) but BEFORE
    /// the sheet dismisses. Use for one-time setup like schema introspection. Same `{KEY}`
    /// substitution as `validation.command`, plus `{AGENT_NAME}` and `{AGENT_DIR}`.
    var postCreateCommand: String? = nil
    var postCreateLabel: String = "Initial setup"

    static let allBuiltIn: [AgentTemplate] = [.git, .jira, .confluence, .database, .figma]

    /// Best-effort match of an existing agent's name back to a built-in template,
    /// so list rows can render the template's icon/color. Matches exact name and
    /// common prefix patterns like `git-helper`, `jira_bot`.
    static func match(agentName: String) -> AgentTemplate? {
        let n = agentName.lowercased()
        return allBuiltIn.first { t in
            n == t.name || n.hasPrefix("\(t.name)-") || n.hasPrefix("\(t.name)_")
        }
    }

    /// Map a template color string (`"blue"`, `"orange"`, …) to a SwiftUI Color.
    /// Shared so list rows and template sheets use the same palette.
    static func swiftUIColor(_ key: String?) -> Color {
        switch key {
        case "orange": return .orange
        case "purple": return DS.Color.purple
        case "blue":   return .blue
        case "green":  return .green
        case "red":    return .red
        case "gray":   return DS.Color.textPrimary
        default:       return DS.Color.accent
        }
    }

    /// Resolve icon+color for an existing agent: user-set icon-asset/icon-symbol/icon-color wins,
    /// falling back to a template match by name, then to the generic person.crop.circle.
    static func iconDescriptor(for agent: Agent) -> (asset: String?, symbol: String, color: Color) {
        let matched = match(agentName: agent.name)
        let asset = agent.iconAsset ?? matched?.assetIcon
        let symbol = agent.iconSymbol ?? matched?.icon ?? "person.crop.circle"
        let color = swiftUIColor(agent.iconColor ?? matched?.color)
        return (asset, symbol, color)
    }
}

struct SecretField: Hashable {
    let key: String
    let label: String
    let placeholder: String
    let help: String
    var isOptional: Bool = false
    var providerIcon: String? = nil   // SF Symbol name
    var providerColor: String? = nil  // "orange" | "purple" | hex
    var providerName: String? = nil   // "GitHub" | "GitLab"
}

struct PlainVarField: Hashable {
    let key: String
    let label: String
    let defaultValue: String
    let help: String
    var isFolder: Bool = false
    var isOptional: Bool = false
}

struct TemplateValidation: Hashable {
    let label: String
    /// Shell command. `{VAR}` placeholders are replaced with var values, `{SECRET}` with secrets.
    let command: String
    let successHint: String
}

/// One database/service connection rendered as a single visual block with
/// alias/scheme/host/user/password/db fields and its own Verify button.
struct ConnectionField: Hashable, Identifiable {
    var id: String { slotId }
    let slotId: String              // logical slot — used as ENV prefix (e.g. "DB1")
    let title: String               // "Connection #1"
    let isOptional: Bool
    let aliasKey: String            // plain var key
    let schemeKey: String           // plain var key (enum-like)
    let schemeOptions: [String]     // dropdown values, e.g. ["postgres","mysql",...]
    let hostKey: String             // plain var key (host or host:port)
    let userKey: String             // plain var key
    let passwordKey: String         // secret key
    let databaseKey: String         // plain var key
    /// Shell command that validates THIS slot only.
    /// `{ALIAS}`, `{SCHEME}`, `{HOST}`, `{USER}`, `{PASSWORD}`, `{DATABASE}` are substituted.
    let verifyCommand: String
}

// Individual templates live in Templates/Template+<Name>.swift

/// Renders a template's brand icon — bundled PNG when available, SF Symbol fallback otherwise.
/// One source of truth used by the popover, sidebar rows, and template sheet.
struct TemplateIcon: View {
    let assetIcon: String?
    let sfSymbol: String
    let tint: Color
    var size: CGFloat = 14

    var body: some View {
        if let asset = assetIcon, let img = Self.loadAsset(asset) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: sfSymbol)
                .foregroundStyle(tint)
                .font(.system(size: size, weight: .semibold))
        }
    }

    /// SwiftPM bundles resources into `Bundle.module`. NSImage(named:) hits the main bundle by
    /// default, which doesn't see them — load from the resource URL directly instead.
    private static func loadAsset(_ name: String) -> NSImage? {
        if let url = Bundle.module.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }
}
