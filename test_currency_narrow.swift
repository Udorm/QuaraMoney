import Foundation

let code = "KHR"
let amount: Decimal = 1000.0

@available(macOS 12.0, *)
func test() {
    let narrow = amount.formatted(.currency(code: code).presentation(.narrow))
    let standard = amount.formatted(.currency(code: code))
    print("Standard: \(standard)")
    print("Narrow: \(narrow)")
}

if #available(macOS 12.0, *) {
    test()
}
