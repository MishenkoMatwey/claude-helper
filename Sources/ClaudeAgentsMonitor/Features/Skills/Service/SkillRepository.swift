import Foundation

protocol SkillRepository {
    func loadAll() -> [Skill]
}

struct SkillRepositoryFile: SkillRepository {
    func loadAll() -> [Skill] { SkillLoader.loadAll() }
}
