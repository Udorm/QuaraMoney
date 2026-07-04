import SwiftUI
struct TestView: View {
    var body: some View {
        List {
            Section {
                Text("Item")
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(8)
    }
}
