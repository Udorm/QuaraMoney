# QuaraMoney

A personal finance app built for the Cambodian market. Track income and expenses, manage multiple wallets, split group expenses, set budgets and savings goals, and scan receipts — all in English and Khmer.

## Features

- **Transaction Tracking** — Log income and expenses with categories, notes, and receipt photos
- **Multi-Currency** — USD and KHR support with live exchange rates and per-transaction rate snapshots
- **Wallets** — Manage multiple wallets (cash, bank accounts, e-wallets) with real-time balances
- **Group Expense Splitting** — Create events, add members, split bills equally or with custom amounts, and calculate minimal settlements
- **Budgets** — Set weekly, monthly, yearly, or custom-period budgets per category with rollover support and threshold alerts (50%/80%)
- **Savings Goals** — Track progress toward financial goals with target amounts and deadlines
- **Debt Tracking** — Record money owed to or by others
- **Recurring Transactions** — Automate repeating income and expenses
- **Receipt Scanning** — Extract transaction details from receipts using on-device Vision
- **Analytics** — Visualize spending patterns and trends
- **Bilingual** — Full English and Khmer localization with runtime language switching
- **Security** — Biometric authentication (Face ID / Touch ID)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI |
| Persistence | SwiftData |
| Architecture | MVVM |
| Min Deployment | iOS 17 |
| Dependencies | None — Apple frameworks only |

Built entirely with Apple-native frameworks: SwiftUI, SwiftData, Combine, Vision, CoreLocation, UserNotifications, and CoreText.

## Architecture

```
View (SwiftUI)
  └── ViewModel (@MainActor, inherits BaseViewModel)
        └── Service / DataService protocol
              └── SwiftData Model (@Model)
```

- **Models** — SwiftData `@Model` classes. All monetary amounts use `Decimal` for precision; event ledger uses `Int64` minor units.
- **ViewModels** — `@MainActor` classes providing business logic to views. All inherit from `BaseViewModel`.
- **Services** — Pure logic layer. `DataService` protocol abstracts persistence with `SwiftDataService` as the production implementation.
- **Views** — Stateless SwiftUI views organized by feature, using `@Query` for live data.

## Project Structure

```
QuaraMoney/
├── Models/              # SwiftData @Model classes
├── ViewModels/          # MVVM view models
├── Services/            # Business logic & data services
├── Views/
│   ├── Home/            # Dashboard
│   ├── Transactions/    # Income & expense management
│   ├── Wallets/         # Wallet management
│   ├── Events/          # Group expense splitting
│   ├── Debts/           # Debt tracking
│   ├── SavingsGoals/    # Savings goal tracking
│   ├── Recurring/       # Recurring transactions
│   ├── Scanning/        # Receipt scanner
│   ├── Analysis/        # Spending analytics
│   ├── Settings/        # App settings
│   ├── Onboarding/      # First-launch flow
│   ├── Components/      # Reusable UI components
│   └── Common/          # Shared view utilities
├── Extensions/          # Swift extensions
├── Scripts/             # Build/utility scripts
└── Resources/
    ├── en.lproj/        # English strings
    └── km.lproj/        # Khmer strings
```

## Requirements

- Xcode 16+
- iOS 17+ simulator or device
- No package managers needed — no CocoaPods, no SPM

## Build & Run

```bash
# Build
xcodebuild -scheme QuaraMoney \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run tests
xcodebuild test -scheme QuaraMoney \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Or open `QuaraMoney.xcodeproj` in Xcode and hit Run.

## License

All rights reserved.
