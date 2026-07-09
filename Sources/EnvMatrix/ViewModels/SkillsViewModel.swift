import Foundation
import AppKit

@MainActor
public final class SkillsViewModel: ObservableObject {
    @Published public var skills: [Skill] = []
    @Published public var errorMessage: String? = nil

    private let service: SkillsService

    public init(service: SkillsService = DefaultSkillsService()) {
        self.service = service
    }

    public func refresh() {
        do {
            self.skills = try service.list()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func toggle(_ skill: Skill) {
        do {
            if skill.isEnabled {
                _ = try service.disable(skill)
            } else {
                _ = try service.enable(skill)
            }
            refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func delete(_ skill: Skill) {
        do {
            try service.delete(skill)
            refresh()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func revealInFinder(_ skill: Skill) {
        NSWorkspace.shared.activateFileViewerSelecting([skill.path])
    }
}
