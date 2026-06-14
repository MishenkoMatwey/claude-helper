import Foundation

struct BashPreset: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let icon: String
    let category: String
    let dangerLevel: DangerLevel
    let patterns: [String]   // raw patterns without "Bash(" wrapper
    let note: String

    enum DangerLevel { case safe, moderate, dangerous }
}

enum BashPresets {
    static let all: [BashPreset] = [
        // Git — read-only, safe operations
        BashPreset(
            label: "Git read-only",
            icon: "doc.text.magnifyingglass",
            category: "Git",
            dangerLevel: .safe,
            patterns: ["git status:*", "git log:*", "git diff:*", "git show:*", "git blame:*", "git branch -l:*", "git remote -v:*"],
            note: "Read-only — no changes to the repo"
        ),
        BashPreset(
            label: "Git safe edit",
            icon: "pencil.line",
            category: "Git",
            dangerLevel: .moderate,
            patterns: [
                "git status:*", "git log:*", "git diff:*", "git show:*",
                "git add:*", "git commit:*", "git checkout:*", "git switch:*",
                "git branch:*", "git stash:*", "git tag:*",
                "git pull:*", "git fetch:*", "git merge:*", "git rebase:*"
            ],
            note: "Local changes + pull/fetch/merge. No push, remote, or reset --hard."
        ),
        BashPreset(
            label: "Git push allowed",
            icon: "arrow.up.circle.fill",
            category: "Git",
            dangerLevel: .moderate,
            patterns: ["git push:*"],
            note: "Push only. Does not include force-push (`git push --force` still needs to be added separately)."
        ),
        BashPreset(
            label: "Git everything (DANGER)",
            icon: "exclamationmark.triangle.fill",
            category: "Git",
            dangerLevel: .dangerous,
            patterns: ["git:*"],
            note: "All git commands including force-push, reset --hard, remote remove. Use with caution."
        ),

        // GitHub CLI
        BashPreset(
            label: "GitHub CLI (gh)",
            icon: "checkmark.shield.fill",
            category: "Git",
            dangerLevel: .moderate,
            patterns: ["gh:*"],
            note: "All gh commands — PRs, issues, releases"
        ),

        // npm / pnpm / yarn
        BashPreset(
            label: "npm",
            icon: "shippingbox.fill",
            category: "Node",
            dangerLevel: .safe,
            patterns: ["npm:*", "npx:*"],
            note: ""
        ),
        BashPreset(
            label: "pnpm",
            icon: "shippingbox.fill",
            category: "Node",
            dangerLevel: .safe,
            patterns: ["pnpm:*", "pnpx:*"],
            note: ""
        ),
        BashPreset(
            label: "yarn",
            icon: "shippingbox.fill",
            category: "Node",
            dangerLevel: .safe,
            patterns: ["yarn:*"],
            note: ""
        ),

        // Java / Maven / Gradle
        BashPreset(
            label: "Maven",
            icon: "hammer.fill",
            category: "JVM",
            dangerLevel: .safe,
            patterns: ["mvn:*", "./mvnw:*", "./mvnw.cmd:*"],
            note: ""
        ),
        BashPreset(
            label: "Gradle",
            icon: "hammer.fill",
            category: "JVM",
            dangerLevel: .safe,
            patterns: ["gradle:*", "./gradlew:*"],
            note: ""
        ),

        // Docker / Kubectl
        BashPreset(
            label: "Docker (read)",
            icon: "shippingbox.fill",
            category: "Containers",
            dangerLevel: .safe,
            patterns: ["docker ps:*", "docker logs:*", "docker images:*", "docker inspect:*"],
            note: "Read state only"
        ),
        BashPreset(
            label: "Docker (full)",
            icon: "shippingbox.fill",
            category: "Containers",
            dangerLevel: .moderate,
            patterns: ["docker:*"],
            note: "All docker commands including run/build/rm"
        ),
        BashPreset(
            label: "Kubectl (read)",
            icon: "circle.grid.cross.fill",
            category: "Containers",
            dangerLevel: .safe,
            patterns: ["kubectl get:*", "kubectl describe:*", "kubectl logs:*", "kubectl top:*"],
            note: "Cluster state read-only"
        ),

        // File system / read-only utils
        BashPreset(
            label: "Read-only utils",
            icon: "doc.text",
            category: "Files",
            dangerLevel: .safe,
            patterns: ["ls:*", "cat:*", "head:*", "tail:*", "less:*", "wc:*", "stat:*", "file:*", "tree:*"],
            note: "File reading and listing"
        ),
        BashPreset(
            label: "Search utils",
            icon: "magnifyingglass",
            category: "Files",
            dangerLevel: .safe,
            patterns: ["grep:*", "rg:*", "find:*", "fd:*", "awk:*", "sed -n:*"],
            note: "grep/find/awk without in-place edit"
        ),

        // Network
        BashPreset(
            label: "curl / network read",
            icon: "globe",
            category: "Network",
            dangerLevel: .safe,
            patterns: ["curl:*", "wget:*", "ping:*", "dig:*", "nslookup:*"],
            note: ""
        ),

        // Python
        BashPreset(
            label: "Python (run scripts)",
            icon: "function",
            category: "Languages",
            dangerLevel: .safe,
            patterns: ["python:*", "python3:*", "pip:*", "pip3:*", "uv:*", "poetry:*"],
            note: ""
        ),
        BashPreset(
            label: "Rust / Cargo",
            icon: "shippingbox.fill",
            category: "Languages",
            dangerLevel: .safe,
            patterns: ["cargo:*", "rustc:*", "rustup:*"],
            note: ""
        ),
        BashPreset(
            label: "Go",
            icon: "circle.dotted",
            category: "Languages",
            dangerLevel: .safe,
            patterns: ["go:*", "gofmt:*"],
            note: ""
        ),
        BashPreset(
            label: "Ruby / Bundler",
            icon: "diamond.fill",
            category: "Languages",
            dangerLevel: .safe,
            patterns: ["ruby:*", "bundle:*", "gem:*", "rake:*"],
            note: ""
        ),
        BashPreset(
            label: "Swift / xcodebuild",
            icon: "swift",
            category: "Languages",
            dangerLevel: .safe,
            patterns: ["swift:*", "xcodebuild:*", "xcrun:*"],
            note: ""
        ),
        BashPreset(
            label: "PHP / Composer",
            icon: "p.square.fill",
            category: "Languages",
            dangerLevel: .safe,
            patterns: ["php:*", "composer:*", "artisan:*"],
            note: ""
        ),

        // Cloud
        BashPreset(
            label: "AWS CLI",
            icon: "cloud.fill",
            category: "Cloud",
            dangerLevel: .moderate,
            patterns: ["aws:*"],
            note: "Full AWS — ALL actions including delete-bucket, terminate-instance"
        ),
        BashPreset(
            label: "AWS read-only",
            icon: "cloud",
            category: "Cloud",
            dangerLevel: .safe,
            patterns: ["aws s3 ls:*", "aws s3 cp:*", "aws ec2 describe:*", "aws logs:*", "aws iam list:*"],
            note: "AWS read-only"
        ),
        BashPreset(
            label: "Google Cloud",
            icon: "cloud.fill",
            category: "Cloud",
            dangerLevel: .moderate,
            patterns: ["gcloud:*", "gsutil:*"],
            note: ""
        ),
        BashPreset(
            label: "Vercel CLI",
            icon: "triangle.fill",
            category: "Cloud",
            dangerLevel: .moderate,
            patterns: ["vercel:*"],
            note: ""
        ),
        BashPreset(
            label: "Firebase",
            icon: "flame.fill",
            category: "Cloud",
            dangerLevel: .moderate,
            patterns: ["firebase:*"],
            note: ""
        ),

        // Infrastructure
        BashPreset(
            label: "Terraform (plan only)",
            icon: "doc.text.magnifyingglass",
            category: "Infra",
            dangerLevel: .safe,
            patterns: ["terraform plan:*", "terraform validate:*", "terraform fmt:*", "terraform show:*", "terraform output:*"],
            note: "No apply/destroy"
        ),
        BashPreset(
            label: "Terraform (full)",
            icon: "exclamationmark.triangle",
            category: "Infra",
            dangerLevel: .dangerous,
            patterns: ["terraform:*"],
            note: "Includes apply/destroy — can provision or tear down infra"
        ),
        BashPreset(
            label: "Ansible (check only)",
            icon: "checkmark.shield",
            category: "Infra",
            dangerLevel: .safe,
            patterns: ["ansible --check:*", "ansible-playbook --check:*"],
            note: "Dry-run, no changes"
        ),
        BashPreset(
            label: "Helm",
            icon: "helm",
            category: "Infra",
            dangerLevel: .moderate,
            patterns: ["helm:*"],
            note: ""
        ),

        // Databases
        BashPreset(
            label: "psql (read)",
            icon: "cylinder.split.1x2",
            category: "Databases",
            dangerLevel: .safe,
            patterns: ["psql -c SELECT:*", "psql -c \\\\d:*", "psql -c \\\\l:*"],
            note: "Only SELECT and \\d \\l"
        ),
        BashPreset(
            label: "psql (full)",
            icon: "cylinder.fill",
            category: "Databases",
            dangerLevel: .dangerous,
            patterns: ["psql:*"],
            note: "Full access — DELETE, DROP included"
        ),
        BashPreset(
            label: "redis-cli",
            icon: "memorychip.fill",
            category: "Databases",
            dangerLevel: .moderate,
            patterns: ["redis-cli:*"],
            note: ""
        ),
        BashPreset(
            label: "mysql (read)",
            icon: "cylinder.split.1x2",
            category: "Databases",
            dangerLevel: .safe,
            patterns: ["mysql -e SELECT:*", "mysql -e SHOW:*", "mysql -e DESC:*"],
            note: ""
        ),

        // System / Process
        BashPreset(
            label: "Process inspect",
            icon: "list.bullet.rectangle",
            category: "System",
            dangerLevel: .safe,
            patterns: ["ps:*", "top:*", "lsof:*", "netstat:*", "ss:*", "df:*", "du:*", "uptime:*", "uname:*"],
            note: "System state read-only"
        ),
        BashPreset(
            label: "systemctl (read)",
            icon: "gearshape.fill",
            category: "System",
            dangerLevel: .safe,
            patterns: ["systemctl status:*", "systemctl list-units:*", "journalctl:*"],
            note: ""
        ),
        BashPreset(
            label: "Homebrew",
            icon: "cup.and.saucer.fill",
            category: "System",
            dangerLevel: .safe,
            patterns: ["brew list:*", "brew info:*", "brew search:*"],
            note: "Read only — no install/uninstall"
        ),

        // SSH / Remote
        BashPreset(
            label: "SSH (any)",
            icon: "network",
            category: "Network",
            dangerLevel: .moderate,
            patterns: ["ssh:*"],
            note: "Full SSH — can execute anything on the remote machine"
        ),
        BashPreset(
            label: "SCP / rsync",
            icon: "arrow.up.arrow.down.circle",
            category: "Network",
            dangerLevel: .moderate,
            patterns: ["scp:*", "rsync:*"],
            note: "File copying"
        ),

        // JSON / YAML utils
        BashPreset(
            label: "jq / yq",
            icon: "doc.text",
            category: "Files",
            dangerLevel: .safe,
            patterns: ["jq:*", "yq:*"],
            note: "JSON/YAML processing"
        ),

        // Build
        BashPreset(
            label: "Make / cmake",
            icon: "hammer",
            category: "JVM",
            dangerLevel: .safe,
            patterns: ["make:*", "cmake:*"],
            note: ""
        ),

        // ─── Frontend (React / Vue / TS) ───
        BashPreset(
            label: "Vite",
            icon: "bolt.fill",
            category: "Frontend",
            dangerLevel: .safe,
            patterns: ["vite:*", "npm run dev:*", "npm run build:*", "npm run preview:*"],
            note: "Vite dev server + build"
        ),
        BashPreset(
            label: "Next.js",
            icon: "n.square.fill",
            category: "Frontend",
            dangerLevel: .safe,
            patterns: ["next:*", "npm run dev:*", "npm run build:*", "npm run start:*"],
            note: ""
        ),
        BashPreset(
            label: "Vue / Nuxt",
            icon: "v.square.fill",
            category: "Frontend",
            dangerLevel: .safe,
            patterns: ["vue:*", "nuxt:*", "npm run dev:*", "npm run build:*"],
            note: ""
        ),
        BashPreset(
            label: "TypeScript / tsc",
            icon: "t.square.fill",
            category: "Frontend",
            dangerLevel: .safe,
            patterns: ["tsc:*", "tsx:*", "ts-node:*"],
            note: ""
        ),
        BashPreset(
            label: "ESLint / Prettier",
            icon: "checkmark.seal.fill",
            category: "Frontend",
            dangerLevel: .safe,
            patterns: ["eslint:*", "prettier:*", "stylelint:*"],
            note: ""
        ),

        // ─── Testing ───
        BashPreset(
            label: "Jest / Vitest",
            icon: "checkmark.circle.fill",
            category: "Testing",
            dangerLevel: .safe,
            patterns: ["jest:*", "vitest:*", "npm test:*", "npm run test:*"],
            note: ""
        ),
        BashPreset(
            label: "Playwright",
            icon: "theatermasks.fill",
            category: "Testing",
            dangerLevel: .safe,
            patterns: ["playwright:*", "npx playwright:*"],
            note: "E2E tests + codegen + headed mode"
        ),
        BashPreset(
            label: "Cypress",
            icon: "eye.fill",
            category: "Testing",
            dangerLevel: .safe,
            patterns: ["cypress:*", "npx cypress:*"],
            note: ""
        ),

        // ─── Spring Boot ───
        BashPreset(
            label: "Spring Boot run",
            icon: "leaf.fill",
            category: "JVM",
            dangerLevel: .moderate,
            patterns: ["./mvnw spring-boot:run:*", "mvn spring-boot:run:*", "./gradlew bootRun:*"],
            note: "Run the service locally"
        ),
        BashPreset(
            label: "Java inspect (jstack/jmap)",
            icon: "magnifyingglass.circle.fill",
            category: "JVM",
            dangerLevel: .safe,
            patterns: ["jstack:*", "jmap:*", "jcmd:*", "jstat:*", "jinfo:*", "java -version:*", "javac -version:*"],
            note: "JVM process diagnostics"
        ),

        // ─── Kafka ───
        BashPreset(
            label: "Kafka topics (read)",
            icon: "list.bullet.rectangle.fill",
            category: "Messaging",
            dangerLevel: .safe,
            patterns: ["kafka-topics --list:*", "kafka-topics --describe:*"],
            note: "List + describe only"
        ),
        BashPreset(
            label: "Kafka topics (full)",
            icon: "list.bullet.rectangle.portrait.fill",
            category: "Messaging",
            dangerLevel: .moderate,
            patterns: ["kafka-topics:*"],
            note: "Includes create/delete topic"
        ),
        BashPreset(
            label: "Kafka consumer/producer",
            icon: "arrow.left.and.right.circle.fill",
            category: "Messaging",
            dangerLevel: .moderate,
            patterns: ["kafka-console-consumer:*", "kafka-console-producer:*", "kafka-consumer-groups:*"],
            note: "Read/write messages + manage group offsets"
        ),
        BashPreset(
            label: "kcat (kafkacat)",
            icon: "bolt.horizontal.circle.fill",
            category: "Messaging",
            dangerLevel: .moderate,
            patterns: ["kcat:*", "kafkacat:*"],
            note: "Universal CLI for Kafka"
        ),

        // ─── Postgres admin ───
        BashPreset(
            label: "pg_dump / pg_restore",
            icon: "arrow.up.bin.fill",
            category: "Databases",
            dangerLevel: .moderate,
            patterns: ["pg_dump:*", "pg_restore:*"],
            note: "Backup and restore"
        ),
        BashPreset(
            label: "Postgres tools",
            icon: "wrench.adjustable.fill",
            category: "Databases",
            dangerLevel: .safe,
            patterns: ["pg_isready:*", "pgbench:*", "vacuumdb:*", "createdb:*"],
            note: "Administration utilities"
        ),
        BashPreset(
            label: "Flyway",
            icon: "arrow.up.doc.on.clipboard.fill",
            category: "Databases",
            dangerLevel: .moderate,
            patterns: ["flyway:*", "./mvnw flyway:*", "./gradlew flywayMigrate:*"],
            note: "DB migrations"
        ),
        BashPreset(
            label: "Liquibase",
            icon: "drop.fill",
            category: "Databases",
            dangerLevel: .moderate,
            patterns: ["liquibase:*"],
            note: "DB migrations"
        ),

        // ─── Misc dev ───
        BashPreset(
            label: "OpenSSL",
            icon: "lock.fill",
            category: "System",
            dangerLevel: .safe,
            patterns: ["openssl:*"],
            note: ""
        ),
        BashPreset(
            label: "ffmpeg / image utils",
            icon: "video.fill",
            category: "Files",
            dangerLevel: .safe,
            patterns: ["ffmpeg:*", "ffprobe:*", "convert:*", "magick:*", "sips:*"],
            note: ""
        ),
    ]

    static func grouped() -> [(category: String, items: [BashPreset])] {
        let groups = Dictionary(grouping: all, by: \.category)
        return groups.keys.sorted().map { ($0, groups[$0]!.sorted { $0.label < $1.label }) }
    }
}
