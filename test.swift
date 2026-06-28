import Foundation

enum Frequency { case daily, weekly, monthly, yearly }

func anchoredNext(current: Date, startDate: Date, component: Calendar.Component) -> Date? {
    let cal = Calendar.current
    var n = max(0, cal.dateComponents([component], from: startDate, to: current).value(for: component) ?? 0) + 1
    var guardN = 0
    while let candidate = cal.date(byAdding: component, value: n, to: startDate),
          candidate <= current, guardN < 1200 {
        n += 1
        guardN += 1
    }
    return cal.date(byAdding: component, value: n, to: startDate)
}

func nextOccurrence(after current: Date, startDate: Date, frequency: Frequency) -> Date? {
    let cal = Calendar.current
    switch frequency {
    case .daily:
        return cal.date(byAdding: .day, value: 1, to: current)
    case .weekly:
        return cal.date(byAdding: .weekOfYear, value: 1, to: current)
    case .monthly:
        return anchoredNext(current: current, startDate: startDate, component: .month)
    case .yearly:
        return anchoredNext(current: current, startDate: startDate, component: .year)
    }
}

func pendingOccurrenceCount(nextDueDate: Date, startDate: Date, frequency: Frequency, endDate: Date?) -> Int {
    let now = Date()
    let cal = Calendar.current
    let tomorrowStart = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
    var count = 0
    var due = nextDueDate
    var guardN = 0
    while due < tomorrowStart, guardN < 1000 {
        if let end = endDate, due > end { break }
        count += 1
        guard let next = nextOccurrence(after: due, startDate: startDate, frequency: frequency) else { break }
        due = next
        guardN += 1
    }
    return count
}

// Test case where it might freeze
let cal = Calendar.current
let startDate = cal.date(from: DateComponents(year: 2025, month: 1, day: 31))!
let nextDueDate = cal.date(from: DateComponents(year: 2025, month: 1, day: 31))!

print("Testing monthly...")
let count = pendingOccurrenceCount(nextDueDate: nextDueDate, startDate: startDate, frequency: .monthly, endDate: nil)
print("Monthly count:", count)

print("Done")
