import SwiftUI
import SwiftData
import OSLog

// MARK: - Main Flow Screen

struct CanvasImportFlowScreen: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var assignmentStore: AssignmentStore
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Assignment.dueDate) private var allAssignments: [Assignment]

    let onImported: (Int) -> Void

    private static let logger = Logger(subsystem: "Struc", category: "CanvasImport")
    private let service = CanvasImportService()

    @State private var phase: Phase = .setup
    @State private var previewAssignments: [ImportedAssignment] = []
    @State private var isShowingPreview = false
    @State private var alertMessage: String?

    private enum Phase {
        case setup
        case connecting
        case fetching
        case done
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .setup:
                    CanvasSetupForm(service: service) { domain, pat in
                        await connectAndFetch(domain: domain, pat: pat)
                    }
                case .connecting:
                    progressView("Connecting to Canvas…")
                case .fetching:
                    progressView("Loading assignments…")
                case .done:
                    EmptyView()
                }
            }
            .navigationTitle("Canvas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $isShowingPreview) {
            GoogleClassroomImportPreviewScreen(assignments: previewAssignments) { count in
                onImported(count)
                dismiss()
            }
            .environmentObject(assignmentStore)
        }
        .alert("Canvas", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { phase = .setup }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func progressView(_ message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connectAndFetch(domain: String, pat: String) async {
        guard let authToken = await authManager.fetchBackendAuthToken() else {
            alertMessage = "Please sign in to import assignments."
            return
        }

        phase = .connecting

        do {
            try await service.connect(domain: domain, accessToken: pat, authToken: authToken)
        } catch let error as CanvasConnectError {
            alertMessage = error.errorDescription
            return
        } catch let error as LMSImportError {
            alertMessage = error.errorDescription
            return
        } catch {
            alertMessage = "Could not connect to Canvas. Check your domain and access token."
            return
        }

        phase = .fetching
        await fetchAssignments(authToken: authToken)
    }

    private func fetchAssignments(authToken: String) async {
        let existingIds = allAssignments.compactMap { a -> String? in
            guard a.source == "canvas" else { return nil }
            return a.externalId
        }

        do {
            let imported = try await service.fetchAssignments(
                existingExternalIds: existingIds,
                authToken: authToken
            )

            if imported.isEmpty {
                alertMessage = "No new Canvas assignments found."
                phase = .setup
                return
            }

            previewAssignments = imported
            phase = .done
            isShowingPreview = true
        } catch let error as LMSImportError {
            alertMessage = error.errorDescription
            phase = .setup
        } catch {
            alertMessage = "Couldn't load Canvas assignments. Please try again."
            phase = .setup
        }
    }
}

// MARK: - Setup Form

private struct CanvasSetupForm: View {
    let service: CanvasImportService
    let onConnect: (String, String) async -> Void

    @State private var domain = ""
    @State private var accessToken = ""
    @State private var isConnecting = false

    private var canConnect: Bool {
        !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {

                // Header
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Label("Connect Canvas", systemImage: "graduationcap.fill")
                        .font(.title2.weight(.bold))

                    Text("Enter your school's Canvas domain and a personal access token to import your assignments.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Domain field
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Canvas domain")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("e.g. myschool.instructure.com", text: $domain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Border.color, lineWidth: 1)
                        )

                    Text("Your school's Canvas URL without https://")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Access token field
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Personal access token")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                    SecureField("Paste your token here", text: $accessToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(DS.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Border.color, lineWidth: 1)
                        )

                    TokenHelpLink()
                }

                // Connect button
                Button {
                    isConnecting = true
                    Task {
                        await onConnect(
                            domain.trimmingCharacters(in: .whitespacesAndNewlines),
                            accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        isConnecting = false
                    }
                } label: {
                    Group {
                        if isConnecting {
                            ProgressView()
                                .tint(DS.Colors.primaryButtonFg)
                        } else {
                            Text("Connect & Import")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(DS.Colors.primaryButtonFg)
                    .background(
                        DS.Colors.primaryButtonBg,
                        in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                    )
                }
                .buttonStyle(PressScaleButtonStyle())
                .disabled(!canConnect || isConnecting)
                .opacity(canConnect && !isConnecting ? 1 : 0.45)
            }
            .padding(.horizontal, DS.Spacing.standard)
            .padding(.vertical, DS.Spacing.section)
        }
        .background(DS.screenBackground)
    }
}

// MARK: - Token Help Link

private struct TokenHelpLink: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "questionmark.circle")
                .font(.caption)
            Text("How to generate a Canvas access token")
                .font(.caption)
        }
        .foregroundStyle(DS.Colors.accent)
        .onTapGesture {
            if let url = URL(string: "https://community.canvaslms.com/t5/Student-Guide/How-do-I-manage-API-access-tokens-as-a-student/ta-p/273") {
                UIApplication.shared.open(url)
            }
        }
    }
}
