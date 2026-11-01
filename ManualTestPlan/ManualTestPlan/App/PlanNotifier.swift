//
//  PlanNotifier.swift
//  ManualTestPlan
//

import Foundation
import UserNotifications

/// Tells the user when an agent has created a plan and is waiting on them.
///
/// A protocol so tests and previews can substitute a recorder instead of triggering real permission prompts.
@MainActor
protocol PlanNotifying: AnyObject {
    /// Called with the plan's ID when the user clicks a notification.
    var onOpenPlan: ((String) -> Void)? { get set }
    /// Announces a newly created plan.
    func planCreated(_ plan: TestPlan) async
}

/// Posts a system notification per new plan. Clicking it opens that plan's window.
///
/// macOS no longer lets a background app take focus, so a plan window created while the user is in their
/// terminal can open behind other windows. The notification is how the user finds out it's there.
@MainActor
final class PlanNotifier: NSObject, PlanNotifying, UNUserNotificationCenterDelegate {
    /// `userInfo` key holding the plan ID.
    nonisolated static let planIDKey = "planID"

    var onOpenPlan: ((String) -> Void)?

    private let center: UNUserNotificationCenter

    /// Creates the notifier and registers as the center's delegate.
    /// - Parameter center: The notification center to use.
    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func planCreated(_ plan: TestPlan) async {
        guard await isAuthorized() else { return }
        let stepCount = plan.progress.total

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = "\(plan.agentName ?? "An agent") is waiting for you to check \(stepCount) step\(stepCount == 1 ? "" : "s")."
        content.sound = .default
        content.userInfo = [Self.planIDKey: plan.id]

        try? await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: nil))
    }

    /// Whether notifications are allowed, asking the first time.
    ///
    /// Authorization is requested when the first plan arrives rather than at launch, so the prompt appears
    /// with context instead of out of nowhere.
    private func isAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional:
            true
        case .notDetermined:
            (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            false
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let planID = response.notification.request.content.userInfo[Self.planIDKey] as? String else { return }
        await MainActor.run { onOpenPlan?(planID) }
    }
}
