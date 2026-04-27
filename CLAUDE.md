# StudyOS

iOS student productivity app. Helps students track assignments, generate smart daily plans, and run timed focus sprints. Built with SwiftUI + SwiftData (iOS client) and a TypeScript/Node.js backend.

## Project Structure

```
StudyOS/                    # iOS app (SwiftUI)
  ContentView.swift         # Core models (Assignment, DailyPlanItem, ConsistencySnapshot) + AssignmentStore + DailyPlanService
  StudyOSApp.swift          # App entry, initializes container/auth/store
  PremiumDesignSystem.swift # Design tokens (DS enum), shared view modifiers
  OnboardingView.swift      # Onboarding flow
  StartModeScreen.swift     # Home / daily plan screen
  WeekViewScreen.swift      # Calendar week view
  AssignmentDetailScreen.swift
  ClassWorkloadScreen.swift
  AnalyticsDashboardScreen.swift
  GoogleClassroomImportPreviewScreen.swift
  Models/
    FocusSprint.swift       # Sprint SwiftData model
    SyncModels.swift        # Sync state enums, SyncDevice
    ModelContainerProvider.swift
  Services/
    AuthManager.swift       # Firebase Auth (Apple, Google, email sign-in)
    AuthCoordinator.swift
    AssignmentStore (in ContentView.swift) # Main observable store
    SprintSessionManager.swift
    CloudSyncManager.swift  # Firestore sync with conflict resolution
    Repositories.swift      # AssignmentRepository, SprintRepository
    SmartNotificationManager.swift
    NotificationManager.swift
    AnalyticsService.swift
    GoogleClassroomImportService.swift
    WeekDateProvider.swift
    GoogleClassroomModels.swift

backend/                    # Node.js/TypeScript backend
  src/
    config/firebase.ts      # Firebase Admin init
    config/google.ts        # Google OAuth client
    services/googleClassroomService.ts
    storage/userAuthRepository.ts
    utils/
```

## Key Architecture

- **AssignmentStore** (`ContentView.swift`) — central `@MainActor ObservableObject`. All assignment mutations go through here.
- **DailyPlanService** — pure scoring logic (no side effects). Builds a 3-slot plan (must/should/quickWin) based on urgency, lateness, and effort fit.
- **CloudSyncManager** — Firestore-backed sync. Uses `SyncMutationEnvelope` queue. Conflict resolution via `syncVersion` and `clientUpdatedAt`.
- **SprintSessionManager** — manages active focus sprint timer, handles scene phase changes.
- **SwiftData models**: `Assignment`, `DailyPlanItem`, `ConsistencySnapshot`, `FocusSprint` — all in `ContentView.swift` or `Models/`.
- **Design system**: Use `DS` enum from `PremiumDesignSystem.swift` for all spacing/colors/radii. Use `.elevatedCard()` modifier for cards.

## Firebase / Auth

- Firebase imports are all guarded with `#if canImport(Firebase*)` for build flexibility.
- Auth supports: Sign in with Apple, Google Sign-In, email/password.
- `AuthManager.AuthState`: `.resolving`, `.signedOut`, `.signedIn(userId:)`, `.error(message:)`.

## Conventions

- `@MainActor` on all stores and managers.
- Use `AssignmentEnergyLevel` enum (low/medium/high) for energy; stored as raw String on model.
- Sync state tracked per-assignment via `SyncState` enum stored as `syncStateRaw: String`.
- `SyncDevice.id` provides a stable per-device identifier.
- Backend is TypeScript; run with Node.js. Source lives in `backend/src/`.
