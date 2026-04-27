import Foundation

enum UpsellTrigger: Hashable {
    case manualAssignmentEntry(count: Int)
    case integrationSettingsTap
    case emptyAppOnSchoolDay
    case focusSprints
    case analytics
    case homeBanner

    var key: String {
        switch self {
        case .manualAssignmentEntry: return "upsell.shown.manualEntry"
        case .integrationSettingsTap: return "upsell.shown.integrationsTap"
        case .emptyAppOnSchoolDay: return "upsell.shown.emptySchoolDay"
        case .focusSprints: return "upsell.shown.focusSprints"
        case .analytics: return "upsell.shown.analytics"
        case .homeBanner: return "upsell.shown.homeBanner"
        }
    }

    var shouldFire: Bool {
        switch self {
        case .manualAssignmentEntry(let count): return count == 3
        default: return true
        }
    }

    var headline: String {
        switch self {
        case .manualAssignmentEntry:
            return "You keep doing this the hard way"
        case .integrationSettingsTap:
            return "Stop typing in your assignments"
        case .emptyAppOnSchoolDay:
            return "Nothing due? Or just not synced?"
        case .focusSprints:
            return "Level up your focus"
        case .analytics:
            return "How productive are you, really?"
        case .homeBanner:
            return "Unlock the full Struc experience"
        }
    }

    var subtext: String {
        switch self {
        case .manualAssignmentEntry:
            return "Connect Classroom and Struc imports your due dates automatically."
        case .integrationSettingsTap:
            return "Connect Google Classroom or Canvas — Struc pulls in due dates automatically."
        case .emptyAppOnSchoolDay:
            return "Connect Classroom to see your real workload in Struc."
        case .focusSprints:
            return "Focus Sprints are a Pro feature. Set a timer, lock in, and track your streak."
        case .analytics:
            return "Unlock stats on your streaks, sprint history, and completion rates."
        case .homeBanner:
            return "Integrations, Focus Sprints, Analytics, and more."
        }
    }
}
