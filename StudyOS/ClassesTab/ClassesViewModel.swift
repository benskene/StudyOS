import Foundation
import SwiftUI
import Combine

@MainActor
final class ClassesViewModel: ObservableObject {
    @Published var courses: [Course] = []
    @Published var selectedCourseId: UUID? = nil  // nil = "All"

    private let storageKey = "struc_courses"

    init() {
        load()
    }

    // MARK: - Course CRUD

    func addCourse(_ course: Course) {
        courses.append(course)
        save()
    }

    func updateCourse(_ course: Course) {
        guard let index = courses.firstIndex(where: { $0.id == course.id }) else { return }
        courses[index] = course
        save()
    }

    func deleteCourse(_ course: Course) {
        courses.removeAll { $0.id == course.id }
        if selectedCourseId == course.id {
            selectedCourseId = nil
        }
        save()
    }

    // MARK: - Pre-population from existing assignment classNames

    func syncFromExistingClassNames(_ classNames: [String]) {
        let existing = Set(courses.map(\.name))
        let palette = Course.paletteHexColors
        var colorIndex = courses.count % palette.count

        for name in classNames where !name.isEmpty && !existing.contains(name) {
            let course = Course(
                name: name,
                teacher: "",
                colorHex: palette[colorIndex % palette.count]
            )
            courses.append(course)
            colorIndex += 1
        }
        save()
    }

    // MARK: - Filtering

    func filteredCourses(allAssignments: [Assignment]) -> [Course] {
        if let id = selectedCourseId {
            return courses.filter { $0.id == id }
        }
        return courses
    }

    func assignments(for course: Course, from all: [Assignment]) -> [Assignment] {
        all.filter { $0.courseName == course.name && !$0.isDeleted }
    }

    func personalAssignments(from all: [Assignment]) -> [Assignment] {
        all.filter { $0.courseName.isEmpty && !$0.isDeleted }
    }

    func color(for course: Course) -> Color {
        Color(hex: course.colorHex)
    }

    func course(for assignment: Assignment) -> Course? {
        courses.first { $0.name == assignment.courseName }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Course].self, from: data) else { return }
        courses = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(courses) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
