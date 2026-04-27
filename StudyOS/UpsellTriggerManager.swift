import Foundation

final class UpsellTriggerManager {
    static let shared = UpsellTriggerManager()
    private init() { recordInstallDateIfNeeded() }

    // MARK: - UserDefaults keys
    private let suppressionKey = "upsell.suppressedUntil"
    private let bannerSuppressionKey = "upsell.banner.suppressedUntil"
    private let installDateKey = "upsell.installDate"
    private let valuePropIndexKey = "upsell.valuePropIndex"

    // MARK: - Session state (in-memory, resets on app foreground)
    private(set) var hasShownUpsellThisSession = false

    func markSessionUpsellShown() {
        hasShownUpsellThisSession = true
    }

    func resetSessionFlag() {
        hasShownUpsellThisSession = false
    }

    // MARK: - Trigger-based upsells

    /// Returns true when the trigger should fire: not Pro, no active sprint,
    /// trigger hasn't fired before, and the "Maybe later" suppression window has expired.
    func shouldShowUpsell(for trigger: UpsellTrigger, isPro: Bool, isSprintActive: Bool) -> Bool {
        guard !isPro else { return false }
        guard !isSprintActive else { return false }
        guard trigger.shouldFire else { return false }
        if let suppressedUntil = UserDefaults.standard.object(forKey: suppressionKey) as? Date,
           Date() < suppressedUntil { return false }
        return !UserDefaults.standard.bool(forKey: trigger.key)
    }

    /// Records that a trigger has fired (permanent, never shows again) and marks the session.
    func markShown(trigger: UpsellTrigger) {
        UserDefaults.standard.set(true, forKey: trigger.key)
        hasShownUpsellThisSession = true
    }

    /// Suppresses all trigger-based upsells for 7 days.
    func suppressForWeek() {
        let until = Date().addingTimeInterval(7 * 24 * 3600)
        UserDefaults.standard.set(until, forKey: suppressionKey)
    }

    // MARK: - Home banner

    /// Returns true when the upgrade banner should appear on the home screen.
    /// Requires: not Pro, no upsell shown this session, 3+ days since install, 14-day suppression clear.
    func shouldShowBanner(isPro: Bool) -> Bool {
        guard !isPro else { return false }
        guard !hasShownUpsellThisSession else { return false }
        guard let installDate = UserDefaults.standard.object(forKey: installDateKey) as? Date,
              Date().timeIntervalSince(installDate) >= 3 * 24 * 3600 else { return false }
        if let suppressedUntil = UserDefaults.standard.object(forKey: bannerSuppressionKey) as? Date,
           Date() < suppressedUntil { return false }
        return true
    }

    /// Suppresses the banner for 14 days and marks the session.
    func suppressBannerForTwoWeeks() {
        let until = Date().addingTimeInterval(14 * 24 * 3600)
        UserDefaults.standard.set(until, forKey: bannerSuppressionKey)
        hasShownUpsellThisSession = true
    }

    // MARK: - Rotating value props

    static let valueProps = [
        "Auto-import assignments",
        "Focus Sprints",
    ]

    /// Returns the next value prop string, cycling through the list on each call.
    func nextValueProp() -> String {
        let index = UserDefaults.standard.integer(forKey: valuePropIndexKey)
        let prop = Self.valueProps[index % Self.valueProps.count]
        UserDefaults.standard.set(index + 1, forKey: valuePropIndexKey)
        return prop
    }

    // MARK: - Install date

    private func recordInstallDateIfNeeded() {
        guard UserDefaults.standard.object(forKey: installDateKey) == nil else { return }
        UserDefaults.standard.set(Date(), forKey: installDateKey)
    }
}
