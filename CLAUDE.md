# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**QuaraMoney** is a personal finance iOS app for the Cambodian market. English + Khmer bilingual, multi-currency (USD/KHR primary). Features: income/expense tracking, wallets, group event expense splitting, debts, budgets, savings goals, receipt scanning.

- **Platform:** iOS 26 deployment target (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`; tests 26.2). Vestigial `#available(iOS 18/26, *)` checks remain in places but are no longer load-bearing.
- **UI:** 100% SwiftUI — no UIKit
- **Persistence:** SwiftData (local) + Supabase cloud sync
- **Architecture:** MVVM
- **Dependencies:** supabase-swift (SPM) for auth/sync/storage; otherwise Apple frameworks only (SwiftUI, SwiftData, Combine, Vision, CoreLocation, UserNotifications, CoreText)

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

Requirements: Xcode 26+, iOS 26 simulator. Dependencies via SPM (supabase-swift); no CocoaPods.

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

### Legacy availability checks

The deployment target is iOS 26, so iOS 26 Liquid Glass APIs (`.glassEffect`, `.buttonStyle(.glass/.glassProminent)`) need no availability guards. `ContentView.swift` still carries a vestigial `#available(iOS 18, *)` split (native `Tab` API vs `NavigationSplitView` + `TabView` fallback) — the iOS-18 branch is the one that runs; the fallback is dead code kept from the iOS 17 era.

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
- Access via `L10n.Group.key` (e.g., `L10n.Common.cancel`)
- **`String+Localization.swift` is auto-generated** — do NOT hand-edit. Regenerate from `.strings` files.
- Adding a string: add to both `.strings` files, then regenerate `String+Localization.swift`
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

### Categories (canonical keys)
- App-defined categories (defaults + system) are identified by a language-independent `Category.canonicalKey` (e.g. `"salary"`, `"sys_debt"`); user-created categories have `nil`
- **All definitions live in `Services/CategoryCatalog.swift`** — seeding, launch "ensure" passes, and `DebtService` resolve categories via `CategoryCatalog.fetchOrCreate(key:in:)`, never by localized name
- The cloud enforces a partial unique index on `(user_id, canonical_key, type)`; the sync engine's dedupe pass merges same-key duplicates deterministically
- Seeding only runs on devices never claimed by a cloud account (`SyncEngine.isLocalStoreAccountOwned`); once owned, categories come from the cloud

### Cloud Sync & Account
- Supabase sync lives in `QuaraMoney/Supabase/` (`SyncEngine`, `SyncMutationTracker`, `SyncRealtime`, `ProfileSyncService`)
- The unified Account screen (`Views/More/AccountView.swift`, reached from the More-tab profile banner) hosts profile identity + auth + sync controls; `AccountViewModel` owns the sync-toggle side effects
- Profile (display name + avatar) syncs to the `profiles` table and is wiped on sign-out/account switch — never let it leak across accounts
- `SyncMutationTracker.isApplyingSyncChanges` must only wrap the engine's *synchronous* write+save spans (`SyncEngine.withSyncWriteGuard`), never an `await` — holding it across suspension points hides concurrent user edits from sync
- Cloud schema changes: update `supabase/migrations/`, mirror into `supabase/schema.sql` + `rls.sql`, and apply to the live project before shipping the client change

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

### Transaction Suggestion Engine
- `TransactionSuggestionEngine` (`Services/TransactionSuggestionEngine.swift`) — pure `@MainActor enum` that ranks wallets and categories for the Add Transaction quick-pickers.
- Scoring model: `recencyDecay × weekdayBoost × hourBoost × coOccurrenceBoost × locationBoost` (all weights in `SuggestionWeights`).
- Key types: `ScoredWallet`, `ScoredCategory` (holds `isHighlighted` for the dominant suggestion), `SuggestionLocationContext` (applePlaceID + spatialKey — for ranking **only**, never persisted to the transaction).
- `AddTransactionView` fetches the device's current location via `CurrentLocationService` in the background on open (new entries only) to supply a `spatialKey` to the engine — this is **never** written to `viewModel.selectedLocation` or saved to the transaction.
- Results are memoized in `@State` in `AddTransactionView` and recomputed on `onAppear` / changes to `type`, `selectedWallet`, `selectedCategory`, `selectedLocation`.
- `AddEventLedgerTransactionViewModel` still uses the old count-based approach — extend if needed.

## Testing

- XCTest with `@testable import QuaraMoney`
- Each test uses fresh in-memory `ModelContainer` via `TestModelContainer.create()`
- Coverage focus: settlement engine, currency conversion, budget rollover
- Follow pattern in `EventSettlementEngineTests.swift`: create container → set up models → call service → assert
