import Foundation

extension Notification.Name {
    static let dataDidUpdate = Notification.Name("dataDidUpdate")
    static let openAddTransaction = Notification.Name("openAddTransaction")
    /// Posted when the user taps a recurring "due" notification (or its Review
    /// action). ContentView switches to the More tab and MoreView pushes the
    /// Recurring screen so the review inbox is one tap away.
    static let openRecurringReview = Notification.Name("openRecurringReview")
    /// Posted when the user taps the drill-in chevron on the Home summary card.
    /// ContentView switches to the Analysis tab and enables Pro mode so the full
    /// analytics dashboard opens.
    static let openProAnalytics = Notification.Name("openProAnalytics")
}
