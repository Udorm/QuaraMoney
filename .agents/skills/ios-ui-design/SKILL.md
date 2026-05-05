---
name: ios-ui-design
user-invocable: true
description: >
  Generate production-ready SwiftUI code for iOS apps with native Apple components
  and Human Interface Guidelines (HIG) compliance. Use this skill whenever the user
  asks to build, design, or prototype any iOS screen or layout — including dashboards,
  transaction lists, summary cards, onboarding, settings, modals, forms, or navigation
  flows. Also trigger for requests like "make this look native iOS", "SwiftUI screen for...",
  "design a [feature] view", or "build a [screen name] in Swift". Always output full screen
  layouts with #Preview macros and mock data. Prioritize native SwiftUI components over
  custom implementations wherever feasible.
---

# iOS UI Design Skill

Produce full-screen SwiftUI layouts that look and feel like first-party Apple apps.
Use native components, system colors, SF Symbols, and HIG-compliant patterns throughout.

---

## Non-Negotiable Defaults

| Concern | Default |
|---|---|
| Framework | SwiftUI only |
| Minimum deployment | iOS 17+ |
| State management | @Observable macro (not @ObservableObject) |
| Colors | Semantic system colors only |
| Icons | Image(systemName:) via SF Symbols 5 |
| Previews | Always — #Preview macro with realistic mock data |
| Output | One complete, copy-pasteable .swift file per screen |

---

## Core Principles

### 1. Native First

Always prefer the native SwiftUI component. Only go custom when a native component
genuinely cannot achieve the goal.

| Need | Use |
|---|---|
| Navigation | NavigationStack + .navigationTitle |
| Lists | List with listStyle(.insetGrouped) or .plain |
| Tabs | TabView with tabItem |
| Modals | .sheet, .fullScreenCover, .confirmationDialog |
| Alerts | .alert modifier |
| Search | .searchable modifier |
| Pull-to-refresh | .refreshable modifier |
| Swipe actions | .swipeActions modifier |
| Pickers | Picker with segmented, wheel, or menu style |
| Charts | Chart from Swift Charts (import Charts) |
| Forms | Form with Section |
| Empty states | ContentUnavailableView |

### 2. Semantic Colors Only
```swift
// Correct
.foregroundStyle(.primary)
.foregroundStyle(.secondary)
.background(.background)
Color(.systemGroupedBackground)
Color(.systemBlue)  // adapts to dark mode automatically

// Wrong — never do this
Color(red: 0.1, green: 0.1, blue: 0.8)
```

### 3. Typography via Dynamic Type
```swift
Text("Balance").font(.largeTitle.bold())
Text("Subtitle").font(.subheadline).foregroundStyle(.secondary)
Text("$1,234.56").font(.title2.monospacedDigit())  // always monospacedDigit for numbers
Text("Note").font(.caption).foregroundStyle(.tertiary)
```

Never use .font(.system(size: 14)) unless truly unavoidable. Max 3–4 font sizes per screen.

### 4. Spacing via 8pt Grid
```swift
.padding()              // 16pt default
.padding(.horizontal)   // safe horizontal inset
VStack(spacing: 8) { }  // tight
VStack(spacing: 12) { } // standard
VStack(spacing: 20) { } // section separation
```

### 5. @Observable State Management (iOS 17+)
```swift
@Observable
final class TransactionViewModel {
    var transactions: [Transaction] = []
    var isLoading = false
    var errorMessage: String?
}

struct TransactionListView: View {
    @State private var viewModel = TransactionViewModel()
}
```

Never use @StateObject, @ObservedObject, or ObservableObject.

---

## Full Screen Layout Recipe
```swift
import SwiftUI

struct ExampleView: View {
    @State private var viewModel = ExampleViewModel()

    var body: some View {
        NavigationStack {
            List {
                // sections and rows
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { }
                }
            }
            .searchable(text: $viewModel.searchText)
            .refreshable { await viewModel.refresh() }
            .overlay {
                if viewModel.items.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView("No Data", systemImage: "tray")
                }
            }
        }
    }
}

#Preview {
    ExampleView()
}
```

---

## Common Patterns

### Hero / Summary Card
```swift
VStack(alignment: .leading, spacing: 4) {
    Text("Total Balance")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    Text("$12,450.00")
        .font(.largeTitle.bold().monospacedDigit())
    Text("+2.4% this month")
        .font(.footnote)
        .foregroundStyle(.green)
}
.frame(maxWidth: .infinity, alignment: .leading)
.padding()
.background(.secondarySystemBackground)
.clipShape(.rect(cornerRadius: 16))
.padding(.horizontal)
```

### Transaction Row
```swift
Label {
    VStack(alignment: .leading, spacing: 2) {
        Text(transaction.merchant).font(.body)
        Text(transaction.date, style: .date)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
} icon: {
    Image(systemName: transaction.categorySymbol)
        .foregroundStyle(transaction.categoryColor)
        .frame(width: 32, height: 32)
        .background(transaction.categoryColor.opacity(0.15))
        .clipShape(.circle)
}
.badge(Text(transaction.amount, format: .currency(code: "USD")))
```

### Empty State
```swift
ContentUnavailableView(
    "No Transactions",
    systemImage: "creditcard.slash",
    description: Text("Transactions will appear once you connect an account.")
)
```

### Swipe Actions
```swift
.swipeActions(edge: .trailing, allowsFullSwipe: true) {
    Button("Delete", role: .destructive) { delete(item) }
}
.swipeActions(edge: .leading) {
    Button("Archive", systemImage: "archivebox") { archive(item) }
        .tint(.orange)
}
```

### Primary CTA Button
```swift
Button("Connect Account") { }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .frame(maxWidth: .infinity)
```

### Sheet with Detents
```swift
.sheet(isPresented: $showAdd) {
    AddView()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
}
```

---

## Mock Data for #Preview
```swift
extension Transaction {
    static let mockList: [Transaction] = [
        Transaction(id: UUID(), merchant: "Whole Foods", amount: -84.32,
                    date: .now, category: .groceries),
        Transaction(id: UUID(), merchant: "Salary Deposit", amount: 3200.00,
                    date: .now.addingTimeInterval(-86400), category: .income),
        Transaction(id: UUID(), merchant: "Netflix", amount: -15.99,
                    date: .now.addingTimeInterval(-172800), category: .subscriptions),
    ]
}
```

---

## Pre-Output Checklist

- [ ] All colors are semantic — no hardcoded hex/RGB
- [ ] All icons use Image(systemName:) with SF Symbols
- [ ] NavigationStack used (not deprecated NavigationView)
- [ ] @Observable + @State used (not @StateObject)
- [ ] Typography uses .font(.) style tokens
- [ ] Monetary/numeric Text uses .monospacedDigit()
- [ ] #Preview macro present with realistic mock data
- [ ] No hardcoded frame sizes where maxWidth: .infinity works
- [ ] ContentUnavailableView used for empty states
- [ ] Icon-only buttons have .accessibilityLabel()

---

## What NOT To Do

- Custom navigation bars built from scratch
- NavigationView (deprecated)
- @StateObject / ObservableObject (iOS 16 pattern)
- Hardcoded hex or RGB colors
- Manual GeometryReader where maxWidth: .infinity works
- Custom tab bars when TabView suffices
- UIViewRepresentable wrapping UIKit when SwiftUI native exists
- More than one .borderedProminent button per screen
- More than 3–4 distinct font sizes on a screen

---

## SF Symbols Quick Reference

**Money & Accounts:** creditcard, creditcard.fill, banknote, banknote.fill,
dollarsign.circle.fill, wallet.pass.fill, building.columns.fill

**Transaction Flow:** arrow.up.right (expense), arrow.down.left (income),
arrow.left.arrow.right (transfer), arrow.uturn.backward (refund), repeat (recurring)

**Categories:** cart.fill, fork.knife, house.fill, car, fuelpump, airplane,
cross.circle.fill, graduationcap, tv, bag.fill, wifi, bolt.fill

**Analytics:** chart.line.uptrend.xyaxis, chart.bar.fill, chart.pie.fill, waveform.path.ecg

**Actions:** plus.circle.fill, pencil, trash, square.and.arrow.up, magnifyingglass,
line.3.horizontal.decrease.circle (filter), bell, gearshape, creditcard.slash

---

## HIG Quick Reference

| Decision | Rule |
|---|---|
| .navigationBarTitleDisplayMode | .large for top-level, .inline for detail |
| .sheet vs .fullScreenCover | sheet for cancellable tasks, fullScreenCover for immersive flows |
| .topBarTrailing | Primary action (add, edit) |
| .topBarLeading | Cancel in modals only |
| List style | .insetGrouped for grouped/settings, .plain for feeds |

### All Screens Must Handle All 4 States
1. **Loading** — ProgressView() or .redacted(reason: .placeholder)
2. **Empty** — ContentUnavailableView with symbol + title + description
3. **Error** — .alert modifier
4. **Content** — the main populated UI
