import Foundation
import BackgroundTasks
import SwiftData

/// Periodic background re-evaluation of recurring rules.
///
/// Due-date reminders are scheduled as one-shot `UNCalendarNotificationTrigger`s
/// that are only re-armed when the app runs (launch, or a post/skip mutation).
/// Without this, a rule that comes due while the app is closed would never get
/// its *next* period's reminder, and the app-icon badge would drift stale.
///
/// `BGAppRefreshTask` lets the system wake us occasionally to: re-arm every
/// rule's reminder and refresh the badge to the current due count. The work is
/// idempotent, so a missed or coalesced run is harmless.
///
/// Requires (Info.plist):
/// - `BGTaskSchedulerPermittedIdentifiers` → `[taskIdentifier]`
/// - `UIBackgroundModes` → `fetch`
enum RecurringBackgroundRefresh {

    nonisolated static let taskIdentifier = "uk.dormmy.QuaraMoney.recurringRefresh"

    /// Earliest the system should consider running the task again. The OS
    /// ultimately decides actual timing based on usage/battery/network.
    nonisolated private static let refreshInterval: TimeInterval = 6 * 3600 // ~4×/day ceiling

    /// Register the task handler. MUST be called before the app finishes
    /// launching (from `application(_:didFinishLaunchingWithOptions:)`).
    /// `nonisolated`: the launch handler is invoked by the system off the main
    /// actor, so it can't call MainActor-isolated members synchronously.
    nonisolated static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Queue the next background run (call when entering the background).
    nonisolated static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("RecurringBackgroundRefresh.schedule failed: \(error)")
            #endif
        }
    }

    nonisolated private static func handle(_ task: BGAppRefreshTask) {
        // Always queue the following run first, so the chain survives even if
        // this execution is cut short.
        schedule()

        let work = Task { @MainActor in
            let context = ModelContext(QuaraMoneyApp.sharedContainer)
            await RecurringNotificationService.rescheduleAll(in: context)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = { work.cancel() }
    }
}
