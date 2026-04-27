import Foundation

struct ImportedAssignment: Codable, Identifiable, Hashable {
    let externalId: String
    let source: String
    let title: String
    let className: String
    let dueDate: String
    let notes: String
    let estMinutes: Int
    let importedAt: String

    var id: String { externalId }

    var dueDateValue: Date? {
        ISO8601DateFormatter.withFractionalSeconds.date(from: dueDate)
            ?? ISO8601DateFormatter().date(from: dueDate)
    }
}

private extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
