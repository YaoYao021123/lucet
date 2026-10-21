import Foundation
import MediaCore

/// Where a lesson opened from editing leads back to: the sliders it was about, and their section.
struct LessonReturn: Equatable {
    let parameters: [AdjustmentParameter]
    let section: String?
}

/// Learning inside editing, as an open door rather than a push: a demo one click away from a slider
/// (its right-click menu) or a section (next to its title, on hover), a "why?" after Auto, and a way
/// back to the photo at the end of the lesson. Nothing opens by itself, nothing counts or nags, and
/// 学习 › 我的学习 can switch it all off.
extension AppModel {
    /// Opens a lesson on this photo, then leads back to `parameters`; nil when links are off or there's no such lesson.
    func demo(_ lessonID: String, parameters: [AdjustmentParameter] = [], section: String? = nil) -> (@MainActor () -> Void)? {
        guard learner.learnLinks, Lesson.lesson(lessonID) != nil else { return nil }
        return { [weak self] in self?.openLesson(lessonID, returning: LessonReturn(parameters: parameters, section: section)) }
    }

    /// "What does this slider do?", for the sliders a lesson shows.
    func demo(for parameter: AdjustmentParameter, section: String?) -> (@MainActor () -> Void)? {
        guard let lesson = Lesson.about(parameter) else { return nil }
        return demo(lesson.id, parameters: [parameter], section: section)
    }

    /// The end of a lesson opened from editing: back to the colour tab with its section open and its
    /// sliders lit for a moment.
    func backToPhoto() {
        let back = lessonReturn
        sheet = nil; lessonReturn = nil
        guard let back else { return }
        inspectorTab = .color
        if let section = back.section { UserDefaults.standard.set(false, forKey: "section.collapsed.\(section)") }
        guard !back.parameters.isEmpty else { return }
        spotlight = Set(back.parameters)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.spotlight = []
        }
    }
}
