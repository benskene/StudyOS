import SwiftUI
import SwiftData
import OSLog

struct GoogleClassroomImportPreviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var assignmentStore: AssignmentStore

    let assignments: [ImportedAssignment]
    let onImported: (Int) -> Void

    @State private var selectedIds: Set<String> = []

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if assignments.isEmpty {
                    ContentUnavailableView(
                        "No assignments found",
                        systemImage: "tray",
                        description: Text("There are no new assignments to import right now.")
                    )
                } else {
                    List(assignments) { assignment in
                        Button {
                            toggleSelection(for: assignment.externalId)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedIds.contains(assignment.externalId) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedIds.contains(assignment.externalId) ? Color.accentColor : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(assignment.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(assignment.className)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(dueText(for: assignment))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }

                VStack(spacing: 10) {
                    Button("Import Selected") {
                        importSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(selectedIds.isEmpty)

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Import Preview")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if selectedIds.isEmpty {
                    selectedIds = Set(assignments.map(\.externalId))
                }
            }
        }
    }

    private func toggleSelection(for id: String) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private func dueText(for assignment: ImportedAssignment) -> String {
        guard let dueDate = assignment.dueDateValue else {
            return "No due date"
        }
        return "Due \(Self.dueDateFormatter.string(from: dueDate))"
    }

    private func importSelected() {
        let selectedAssignments = assignments.filter { selectedIds.contains($0.externalId) }
        let importedCount = assignmentStore.importAssignments(selectedAssignments)
        onImported(importedCount)
        dismiss()
    }
}

struct LMSImportFlowScreen: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]

    let provider: any LMSProvider
    let onImported: (Int) -> Void

    private static let logger = Logger(subsystem: "Struc", category: "LMSImportFlow")
    @State private var isLoading = false
    @State private var isCheckingAvailability = true
    @State private var availability: LMSImportAvailability = .blocked(reason: "Checking import availability…")
    @State private var statusMessage: String?
    @State private var previewAssignments: [ImportedAssignment] = []
    @State private var isShowingPreview = false
    @State private var alertMessage: String?
    @State private var hasShownBlockingUnavailableAlert = false

    var body: some View {
        VStack(spacing: 18) {
            if isCheckingAvailability {
                ProgressView("Checking \(provider.displayName) integration…")
            } else if isLoading {
                ProgressView("Connecting \(provider.displayName)…")
            } else {
                Button("Import from \(provider.displayName)") {
                    Task {
                        if case .blocked(let reason) = availability {
                            alertMessage = reason
                            return
                        }
                        await startImportFlow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isImportEnabled)
            }

            if case .blocked(let reason) = availability {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await runPreflightIfNeeded()
        }
        .onChange(of: authManager.authState) { _ in
            Task { await runPreflightIfNeeded() }
        }
        .sheet(isPresented: $isShowingPreview) {
            GoogleClassroomImportPreviewScreen(assignments: previewAssignments) { importedCount in
                onImported(importedCount)
                dismiss()
            }
            .environmentObject(assignmentStoreForSheet)
        }
        .alert(provider.displayName, isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @EnvironmentObject private var assignmentStoreForSheet: AssignmentStore

    private var isImportEnabled: Bool {
        if case .available = availability {
            return true
        }
        return false
    }

    private func runPreflightIfNeeded() async {
        isCheckingAvailability = true
        let availability = await provider.preflightAvailability(isAuthenticated: authManager.currentUserId != nil)
        self.availability = availability
        isCheckingAvailability = false
        if case .blocked(let reason) = availability, !hasShownBlockingUnavailableAlert {
            alertMessage = reason
            hasShownBlockingUnavailableAlert = true
        }
    }

    private func startImportFlow() async {
        guard !isLoading else { return }
        guard isImportEnabled else {
            if case .blocked(let reason) = availability {
                alertMessage = reason
            }
            return
        }

        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        let existingExternalIds: [String] = assignments.compactMap { assignment -> String? in
            guard assignment.source == provider.id else { return nil }
            return assignment.externalId
        }

        let authToken = await authManager.fetchBackendAuthToken()

        do {
            let imported = try await provider.connectAndFetchAssignments(
                existingExternalIds: existingExternalIds,
                authToken: authToken
            )

            if imported.isEmpty {
                statusMessage = "No new assignments were found right now."
                return
            }

            previewAssignments = imported
            isShowingPreview = true
        } catch let error as LMSImportError {
            let message = error.errorDescription ?? "Couldn't import assignments right now."
            Self.logger.error("LMS import failed: \(message, privacy: .public)")
            statusMessage = message
            alertMessage = message
        } catch {
            let message = "Couldn't import assignments right now. Please try again shortly."
            Self.logger.error("LMS import failed unexpectedly: \(error.localizedDescription, privacy: .public)")
            statusMessage = message
            alertMessage = message
        }
    }
}
