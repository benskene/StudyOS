import SwiftUI

struct AddCourseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ClassesViewModel

    var editingCourse: Course?

    @State private var name: String
    @State private var teacher: String
    @State private var selectedColorHex: String

    init(viewModel: ClassesViewModel, editingCourse: Course? = nil) {
        self.viewModel = viewModel
        self.editingCourse = editingCourse
        _name = State(initialValue: editingCourse?.name ?? "")
        _teacher = State(initialValue: editingCourse?.teacher ?? "")
        _selectedColorHex = State(initialValue: editingCourse?.colorHex ?? Course.defaultColorHex)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.largeSection) {
                Text(editingCourse == nil ? "New Class" : "Edit Class")
                    .font(.largeTitle)

                // Name
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Class name")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("e.g. AP Biology", text: $name)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Border.color, lineWidth: 1)
                        )
                }

                // Teacher
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Teacher (optional)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("e.g. Ms. Johnson", text: $teacher)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Border.color, lineWidth: 1)
                        )
                }

                // Color picker
                VStack(alignment: .leading, spacing: DS.Spacing.micro) {
                    Text("Color")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 6),
                        spacing: DS.Spacing.micro
                    ) {
                        ForEach(Course.paletteHexColors, id: \.self) { hex in
                            colorSwatch(hex: hex)
                        }
                    }
                }

                // Actions
                VStack(spacing: 10) {
                    Button(action: save) {
                        Text("Save")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(DS.Colors.primaryButtonFg)
                            .background(
                                DS.Colors.primaryButtonBg,
                                in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)

                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, DS.Spacing.standard)
            .padding(.vertical, DS.Spacing.standard)
        }
        .background(DS.screenBackground)
    }

    @ViewBuilder
    private func colorSwatch(hex: String) -> some View {
        let isSelected = hex == selectedColorHex
        Button {
            selectedColorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 40, height: 40)
                .overlay {
                    if isSelected {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if var existing = editingCourse {
            existing.name = trimmedName
            existing.teacher = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.colorHex = selectedColorHex
            viewModel.updateCourse(existing)
        } else {
            let course = Course(
                name: trimmedName,
                teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
                colorHex: selectedColorHex
            )
            viewModel.addCourse(course)
        }
        dismiss()
    }
}
