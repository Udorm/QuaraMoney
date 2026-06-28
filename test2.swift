import Foundation

let cal = Calendar.current
let startDate = Date.distantPast
let current = Date()

let components = cal.dateComponents([.month], from: startDate, to: current)
print(components.month)
