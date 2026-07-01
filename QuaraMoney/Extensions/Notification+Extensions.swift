import Foundation

extension Notification.Name {
    static let dataDidUpdate = Notification.Name("dataDidUpdate")
    static let openAddTransaction = Notification.Name("openAddTransaction")
    /// Posted when the user taps a recurring "due" notification (or its Review
    /// action). ContentView switches to the More tab and MoreView pushes the
    /// Recurring screen so the review inbox is one tap away.
    static let openRecurringReview = Notification.Name("openRecurringReview")
}
