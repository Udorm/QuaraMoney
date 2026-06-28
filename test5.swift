import Foundation
let cal = Calendar.current
let next = cal.date(byAdding: .day, value: 1, to: Date.distantPast)!
print(next == Date.distantPast)
