import Foundation

let cal = Calendar.current
var current = cal.date(from: DateComponents(year: 2024, month: 12, day: 30))!
for _ in 0..<10 {
    let next = cal.date(byAdding: .weekOfYear, value: 1, to: current)!
    print(next)
    current = next
}
