# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

**QuaraMoney** is a personal finance iOS app for the Cambodian market. English + Khmer bilingual, multi-currency (USD/KHR primary). Features: income/expense tracking, wallets, group event expense splitting, debts, budgets, savings goals, receipt scanning.

- **Platform:** iOS 17+ (iOS 18 features behind `#available` checks)
- **UI:** 100% SwiftUI — no UIKit
- **Persistence:** SwiftData
- **Architecture:** MVVM
- **No third-party dependencies** — Apple frameworks only (SwiftUI, SwiftData, Combine, Vision, CoreLocation, UserNotifications, CoreText)

## Build & Test Commands

```bash
# Build
xcodebuild -scheme QuaraMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run all tests
xcodebuild test -scheme QuaraMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Run a single test
xcodebuild test -scheme QuaraMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:QuaraMoneyTests/CurrencyManagerTests/testConversionSameCurrency

# Run a single test class
xcodebuild test -scheme QuaraMoney -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:QuaraMoneyTests/EventSettlementEngineTests
```

Requirements: Xcode 16+, iOS 17+ simulator. No CocoaPods/SPM — pure Xcode project.

## Architecture

### MVVM Pattern

```
View (SwiftUI @Query / @State)
  └── ViewModel (@MainActor @Published, inherits BaseViewModel)
        └── Service / DataService protocol
              └── SwiftData Model (@Model)
```

- **Models** — `@Model` classes in `Models/`. All money amounts use `Decimal`; event ledger uses `Int64` minor units via `MoneyMinorUnitConverter`.
- **ViewModels** — `@MainActor` classes in `ViewModels/`. All inherit `BaseViewModel` (provides `dataService`, `isLoading`, `errorMessage`). Use `Task.detached` with `PersistentIdentifier` for background work.
- **Services** — Pure logic in `Services/`. `DataService` protocol abstracts persistence; `SwiftDataService` is the production impl.
- **Views** — In `Views/` organized by feature. Stateless where possible. Use `@Query` for live SwiftData queries.

### Global Singletons

| Singleton | Purpose |
|-----------|---------|
| `CurrencyManager.shared` | Exchange rates (24h cache), currency conversion |
| `LanguageManager.shared` | Runtime language switching, `fontRefreshID` forces view rebuild |
| `HapticManager.shared` | Haptic feedback |
| `NotificationManager.shared` | Local push notifications |
| `SecurityManager.shared` | Biometric auth / encryption |

### Data Flow

- `NotificationCenter` broadcasts `.dataDidUpdate` after any write so views refresh
- `ModelContext` is always on `@MainActor`; pass `PersistentIdentifier` across actor boundaries
- `ModelContainer` created once in `QuaraMoneyApp` and injected via `.modelContainer(_:)`

### iOS 17 vs iOS 18

`ContentView.swift` uses `#available(iOS 18, *)`: iOS 18 uses native `Tab` API, iOS 17 falls back to `NavigationSplitView` + `TabView`. Preserve both code paths when modifying navigation.

## Key Conventions

### Money Handling
- **Always `Decimal`, never `Double` or `Float`** for monetary amounts
- Event ledger uses `Int64` minor units (100 = $1.00) via `MoneyMinorUnitConverter`
- Exchange rates stored per-transaction at creation time (not recalculated)
- `CurrencyManager.shared.convert(amount:from:to:)` for runtime conversions
- Fallback rates: USD = 1.0, KHR = 4000.0

### SwiftData
- Model edits must happen on `@MainActor` `ModelContext`
- Pass `PersistentIdentifier` (not model objects) across actor boundaries
- Relationships: `.cascade` for owned children, `.nullify` for references
- `@Transient` for computed/cached fields (e.g., `_cachedBalance` on `Wallet` — may be stale, recalculate when correctness matters)

### Localization
- Two languages: English (`en.lproj/`) and Khmer (`km.lproj/`)
- Keys use dot-namespaced format: `"common.cancel"`, `"transaction.add_income"`
- Access using either the generated `L10n.Group.key` constants or the live `"key".localized` convention used by Plan and Pro Analytics
- **`String+Localization.swift` is auto-generated** — never hand-edit it
- Adding an `L10n` constant: add the key to both `.strings` files, then regenerate `String+Localization.swift` using the established generator
- Adding a `.localized` key: add it to both `.strings` files and run `python3 Scripts/check_missing_keys.py`; no generated constant is required
- Runtime language switch via `LanguageManager.shared`; posts `.languageDidChange` notification

### Font System
- **Always use `.appFont(size:weight:)` modifier** — never `.system(size:)` or `UIFont.systemFont`
- `Font+Khmer.swift` cascade: SF Pro for Latin, MiSans Khmer for Khmer script
- `MiSansKhmerVF.ttf` registered in `Info.plist` under `UIAppFonts`

### Naming
| Category | Convention | Example |
|----------|-----------|---------|
| Types | PascalCase | `TransactionType`, `BudgetPeriodType` |
| Properties/functions | camelCase | `isLoading`, `fetchRates()` |
| Private backing stores | `_` prefix | `_cachedBalance` |
| Localization keys | `dot.namespaced` | `"common.save"` |

## Complex Modules

### Event Expense Splitting (most complex feature)
- `Event` → `[EventMember]` + `[EventLedgerTransaction]` (amounts as `Int64` minor units, `splitType`: equal/custom/payerOnly)
- `EventSettlementEngine`: greedy minimal-transfer algorithm
- `EventSettlementSnapshot`: persisted settlement state
- **`EventDetailViewV2`** is the active view — `EventDetailView`/`EventDetailViewV3` are deleted
- Mode: `Event.EventLedgerMode` — `.legacyLinked` (older) vs `.isolatedV1` (current)

### Budget System
- `Budget` → `Category` with `periodType` (weekly/monthly/yearly/custom)
- `BudgetRolloverService` handles period transitions
- `BudgetNotificationService` fires alerts at 50%/80% of limit

## Testing

- XCTest with `@testable import QuaraMoney`
- Each test uses fresh in-memory `ModelContainer` via `TestModelContainer.makeTestContainer()`
- Coverage focus: settlement engine, currency conversion, budget rollover
- Follow pattern in `EventSettlementEngineTests.swift`: create container → set up models → call service → assert
