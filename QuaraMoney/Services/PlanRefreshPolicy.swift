import Foundation
import Observation

/// Shared invalidation contract used by all five Plan screen levels.
///
/// Screens provide their generation-checked loader as `refreshAction`. Data
/// notifications are visibility-gated; appearance and foreground activation
/// always request a refresh so day/timezone-derived metrics cannot go stale.
@MainActor
@Observable
final class PlanRefreshPolicy {
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshAction: (() -> Void)?
    @ObservationIgnored private var isVisible = false
    @ObservationIgnored private var needsRefresh = true

    init() {
        let names: [Notification.Name] = [
            .dataDidUpdate,
            .currencyRatesDidChange,
            .preferredCurrencyDidChange,
            .languageDidChange,
            .NSCalendarDayChanged,
            .NSSystemTimeZoneDidChange,
            Notification.Name("UIApplicationSignificantTimeChangeNotification")
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.invalidate() }
            }
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func configure(refresh: @escaping () -> Void) {
        refreshAction = refresh
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        if visible {
            needsRefresh = false
            refreshAction?()
        }
    }

    func sceneBecameActive() {
        invalidate()
    }

    func invalidate() {
        if isVisible {
            refreshAction?()
        } else {
            needsRefresh = true
        }
    }
}
