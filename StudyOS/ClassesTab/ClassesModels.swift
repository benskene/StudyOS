import Foundation

struct Course: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var teacher: String
    var colorHex: String
}

extension Course {
    static let defaultColorHex = "#45B7D1"

    static let paletteHexColors: [String] = [
        "#FF6B6B", "#FF8E53", "#FECA57", "#1DD1A1",
        "#48DBFB", "#45B7D1", "#54A0FF", "#5F27CD",
        "#FF9FF3", "#00D2D3", "#C8D6E5", "#576574"
    ]
}
