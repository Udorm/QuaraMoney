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

let start = Date()
let cal = Calendar.current
let startDate = cal.date(from: DateComponents(year: 2000, month: 1, day: 1))!

for _ in 0..<10 {
    var due = startDate
    let tomorrowStart = cal.date(from: DateComponents(year: 2026, month: 6, day: 29))!
    var count = 0
    var guardN = 0
    while due < tomorrowStart, guardN < 1000 {
        count += 1
        guard let next = nextOccurrence(after: due, startDate: startDate, frequency: .daily) else { break }
        due = next
        guardN += 1
    }
}
print("Daily time: \(Date().timeIntervalSince(start))")

let start2 = Date()
for _ in 0..<10 {
    var due = startDate
    let tomorrowStart = cal.date(from: DateComponents(year: 2026, month: 6, day: 29))!
    var count = 0
    var guardN = 0
    while due < tomorrowStart, guardN < 1000 {
        count += 1
        guard let next = nextOccurrence(after: due, startDate: startDate, frequency: .monthly) else { break }
        due = next
        guardN += 1
    }
}
print("Monthly time: \(Date().timeIntervalSince(start2))")

