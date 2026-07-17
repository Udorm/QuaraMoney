# QuaraMoney UX/UI Audit — July 2026

**Method:** code-only audit per `PLAN.md` (locked via grill + 4-round Codex review).
**Audited commit:** `2804c7f` (main). Tree state: clean except untracked `QuaraMoney/PLAN.md`, `QuaraMoney/PLAN-REVIEW-LOG.md`, `sonar-project.properties`.
**Platform baseline:** iOS 26 deployment target; iOS 26 HIG / Liquid Glass is the conformance reference. (CLAUDE.md's residual "iOS 17+" notes are not authoritative.)
**Ranking lens:** new-user first session weighted heaviest; P1 reserved for blocked completion / access loss / data-loss risk / severe unavoidable friction. Journey weighting orders findings within a tier only.
**First-session journeys (mapped from code):**
- (a) Clean install → language choice → tour → currency choice → auto-created starter "Cash" wallet (`OnboardingView.swift:444`) → Home → first transaction.
- (b1) Launch with restored local store — onboarding still runs if `isOnboardingCompleted` was reset, but wallet creation is skipped when wallets exist.
- (b2) Fresh reinstall → onboarding → post-onboarding cloud sign-in via Account → possible local/cloud conflict (`DataConflictResolutionView`).
- (c) Starter-wallet failure / all wallets deleted → `ContentView.onAppear` forces `AddWalletView` as a sheet (`ContentView.swift:83-107`).

**Error channels (mapped):** predominantly view-local `@State` + `.alert`; root `ErrorService` alert at app level; `BaseViewModel.errorMessage` in the minority of VMs that inherit it. Findings below are judged against the channel each flow actually uses.

---

## Executive summary — top 5 themes

The app is in **strong pre-launch shape**: localization discipline in views is near-total, empty states are standardized, destructive deletes mostly have confirmation + undo, and the recently redesigned areas (wallets, debts, analytics) hold together. **No P1 findings** — nothing blocks task completion, loses access, or destroys data without warning. The room for improvement clusters into five themes:

1. **The bilingual promise stops at the app's edge.** Every notification a Khmer user receives is partly or fully English — hardcoded reminder copy, English enum raw-values as alert titles, and an English Face ID prompt. These are the app's only user-facing surfaces that ignore `LanguageManager`.
2. **Silent failure in the receipt-scan flow.** The marquee "scan a receipt" feature has no progress indicator, mutates form fields whenever the async OCR lands, and reports failure with nothing but a haptic. New users will conclude scanning "doesn't work."
3. **Destructive-action friction is inconsistent.** Delete-account gets a confirmation dialog; sign-out is one tap with none. Delete-all-transactions is irreversible behind a single generic alert while individual deletes get undo toasts.
4. **Permission dead ends.** The daily-reminder toggle silently snaps off when notification permission was denied, with no explanation or path to Settings; camera denial in the scanner has no pre-flight handling.
5. **Accumulated dead UI and un-tokenized accents.** An unreachable notification center (443 lines), an unused filter menu, an empty component file, and 29 hardcoded `.blue` tints against an *empty* AccentColor asset — the app has no defined brand accent at all.

---

## P2 findings (meaningful friction / clear violations)

### P2-1 · Receipt scanning fails and succeeds silently
**Screens:** Add Transaction (classic + compact) · **Evidence:** `QuaraMoney/Views/Transactions/AddTransactionView.swift:525-539` (`ScannerView` sheet, `case .failure` → DEBUG-only print), `QuaraMoney/ViewModels/AddTransactionViewModel.swift:274-325` (`scanReceipt` catch → haptic only; no loading state), same pattern at `CompactAddTransactionView.swift:313`.
**Condition:** user taps scan on a new transaction.
**Why it hurts:** first-session users trying the highest-delight feature get: (1) no indication OCR is running (cloud Gemini calls can take seconds), (2) fields that suddenly change under their fingers — a scan finishing late overwrites an amount they've started typing, (3) on failure (bad API key, offline, unreadable receipt) nothing at all except a haptic. The feature reads as broken rather than failed.
**Fix sketch:** add an `isScanning` published state → progress overlay/chip on the form; surface failure through the existing error channel with a reason ("couldn't read receipt", "check API key in Settings"); skip applying results if the user edited the amount after initiating the scan.
**Effort:** M

### P2-2 · Notifications and system prompts are English-only for Khmer users
**Surfaces (non-view):**
- `QuaraMoney/Managers/NotificationManager.swift:67-68` — daily reminder title/body hardcoded ("Time to log your expenses! 📝").
- `QuaraMoney/Services/BudgetRolloverService.swift:160-161` — rollover notification hardcoded English.
- `QuaraMoney/Services/BudgetNotificationService.swift:158` — alert **title** is `alertType.rawValue` ("50% Spent", `Budget.swift:368-372`) while the **body** is properly localized — mixed-language notifications.
- `QuaraMoney/Managers/SecurityManager.swift:30` — `LAContext` `localizedReason: "Unlock QuaraMoney"` hardcoded; the Face ID/passcode sheet shows English to Khmer users.
**Why it hurts:** notifications are the app speaking to the user unprompted — for the Khmer-market differentiator, these are exactly the wrong places to be English. (`RecurringNotificationService` and the daily-summary title do it correctly via L10n, so the pattern exists.)
**Fix sketch:** route all four sites through L10n keys in both `.strings` files; give `BudgetAlertType` a `localizedTitle` and stop using `rawValue` for display. Note: `NotificationManager` copy is baked at schedule time — re-schedule pending notifications on `.languageDidChange`.
**Effort:** S

### P2-3 · Daily-reminder toggle dead-ends when permission is denied
**Screen:** Settings · **Evidence:** `QuaraMoney/Views/Settings/SettingsView.swift:139-141` (`requestPermission()` on toggle-on), `QuaraMoney/Managers/NotificationManager.swift:46-58` (denied → `isDailyReminderEnabled = false`, nothing else).
**Condition:** user previously denied notification permission (or denies the prompt), then enables the toggle.
**Why it hurts:** the toggle visibly snaps back off with zero explanation. There is no "notifications are disabled for QuaraMoney — open Settings" path, so the user can't succeed no matter how many times they try.
**Fix sketch:** when `requestAuthorization` returns denied, publish a state the Settings view turns into an alert with an "Open Settings" button (`UIApplication.openSettingsURLString`).
**Effort:** S

### P2-4 · Sign-out is one tap with no confirmation
**Screen:** Account · **Evidence:** `QuaraMoney/Views/More/AccountView.swift:443-459` (button → `auth.signOut()` directly; contrast delete-account at `:469-508`, which gets a `confirmationDialog`).
**Condition:** signed-in user taps Sign Out — possibly accidentally, in the same visual card group as other actions.
**Why it hurts:** sign-out wipes the profile (by design, to prevent cross-account leakage) and detaches the device from sync; if a sync hadn't completed, locally-made edits stop replicating until re-sign-in. An irreversible-feeling account action with less friction than "remove photo" (which does get a destructive-role dialog) is inverted friction.
**Fix sketch:** add a confirmation dialog matching the delete-account pattern; mention unsynced-changes implications in the message when `sync.lastError != nil` or a sync is pending.
**Effort:** S

### P2-5 · "Delete All Transactions" is irreversible behind one generic alert
**Screen:** Settings · **Evidence:** `QuaraMoney/Views/Settings/SettingsView.swift:239-258` (production button), `:307-325` (single alert → `deleteAllTransactions()`).
**Condition:** any user, two taps total.
**Why it hurts:** individual transaction deletes get an undo toast; the bulk version — which tombstones *everything* and replicates the deletion to the cloud — gets a single alert whose message doesn't say how many transactions are about to go. For a finance app this is the single most consequential button in Settings.
**Fix sketch:** include the live transaction count in the alert message (fetchCount is one line), require a second explicit step (e.g. confirmation dialog listing "Delete N transactions" as the destructive action), and fire a success confirmation after.
**Effort:** S

### P2-6 · The forced create-wallet sheet can be dismissed into a wallet-less app
**Screens:** ContentView / AddWalletView · **Evidence:** `ContentView.swift:83-87` (`onAppear` shows sheet once), `:104-107` (`.interactiveDismissDisabled()`), `QuaraMoney/Views/Wallets/AddWalletView.swift:101-107` (unconditional ✕ cancel button dismisses).
**Condition:** journey (c) — starter-wallet creation failed or user deleted every wallet; then taps ✕ on the forced sheet.
**Why it hurts:** `interactiveDismissDisabled` blocks swipe-down but the toolbar ✕ still works; `onAppear` won't re-fire, so the user sits in an app that can't record transactions until relaunch. Mitigation exists — Add Transaction shows `TransactionSetupPrompt` to create a wallet inline — so this is a snag, not a dead end.
**Fix sketch:** in the forced (wallets-empty) presentation, hide the ✕ (pass a flag) or re-present on sheet dismissal while `wallets.isEmpty`.
**Effort:** S

### P2-7 · Events — the flagship splitting feature — is filed under "Insights"
**Screen:** More · **Evidence:** `QuaraMoney/Views/More/MoreView.swift:88-104` (Events row inside `Section(L10n.More.insights)` next to Budget Insights).
**Condition:** any user looking for expense splitting.
**Why it hurts:** Events is the app's most complex, most differentiated feature, and it's the second row of a section whose header promises analytics. New users scanning More for "split with friends" have no scent trail; "Insights" actively mislabels it.
**Fix sketch:** move Events into the Management section (with Wallets/Debts — it manages money movements) or give it its own section; longer-term consider whether Events deserves surface area outside More.
**Effort:** S

---

## P3 findings (polish / consistency — capped, deduplicated)

1. **Debug scaffolding in shipped onboarding** — `OnboardingView.swift:29-30`: "TEMP DEBUG" `ONB_PAGE` env-var jump. Harmless on device but explicitly marked temporary; remove or wrap in `#if DEBUG`. (S)
2. **29 hardcoded `.blue` interactive tints + empty AccentColor asset** — `Assets.xcassets/AccentColor.colorset/Contents.json` defines no color, so the accent is default system blue, and selection checkmarks/tints hardcode `.blue` (e.g. `ExportOptionsView.swift:179`, `SelectableRow.swift:45-51`, `TransactionCategoryPickerSheet.swift:234`, `EventDetailViewV2.swift:157`). Works today only because both happen to be blue. Define a brand accent once, replace `.blue` with `.tint`/`Color.accentColor`. (M — mechanical but wide)
3. **Tab-bar label construction inconsistent between iPad and iPhone branches** — `ContentView.swift:21-59` (manual `VStack` + `.appFont(.caption2)` labels) vs `:64-78` (system `Tab(_:systemImage:)`); also `"tab.plan".localized` string-key style vs `L10n.Tab.*` for its siblings. Unify on the system form unless the custom font is load-bearing on iPad. (S)
4. **Raw `.font(.subheadline)` on the day-header add button** — `HomeView.swift:346`; everything around it uses `.appFont`. (S)
5. **Onboarding starter wallet hardcodes `#007AFF`** — `OnboardingView.swift:454`; if a brand accent is defined (P3-2), seed with it. (S)
6. **Export custom range accepts start > end** — `ExportOptionsView.swift:14-15` (both default `Date()`), `:153-154` (no validation) → silently empty CSV. Clamp or disable the button. (S)
7. **Shipped thinking-out-loud comments in wallet selection** — `ExportOptionsView.swift:168-191` ("selecting 'All' does nothing or deselects specific?"). Tidy the logic and comments; behavior itself is fine. (S)
8. **Drill-down empty state is a bare secondary label** — `TransactionListView.swift:25-27` renders `Text` for the empty case; when it's the *whole* body of `FilteredTransactionsDetailView` (tapping an analytics category with no rows in period), the screen looks unfinished next to `AppEmptyStateView` everywhere else. Pass a flag or wrap at the call site. (S)
9. **`saveWallet()` fires the success haptic unconditionally** — `AddWalletViewModel.swift:38-58`: the guard-fail path is unreachable via UI (button disabled), but the haptic-then-dismiss pattern gives false success if `dataService.insert` ever fails silently; also the insert path posts no `.dataDidUpdate` from the VM. Low impact, worth a tidy when touched. (S)

*Overflow appendix:* `HomeView.swift:147-162` `summaryHeader`/`walletFilterDescription` are dead private members — see Dead UI below.

---

## Unreachable / dead UI (report separately from live findings)

| Item | Evidence | Status |
|---|---|---|
| `NotificationCenterView` + `NotificationBellButton` (443-line notification inbox) | `Views/Components/NotificationCenterView.swift`; zero external references | Unreachable — no production entry point. Mount it (the bell was presumably meant for Home) or delete it; `BudgetNotificationService` records in-app alerts that currently have no reader. |
| `FilterMenuView` | `Views/Components/FilterMenuView.swift:15`; zero external references | Unused generic — superseded by `FilterSheetView`. Delete. |
| `AppearancePickers.swift` | `Views/Components/AppearancePickers.swift` — **0 lines, empty file** | Delete the file. |
| `HomeView.summaryHeader` / `walletFilterDescription` | `HomeView.swift:147-162` | Dead private members. Delete. |

---

## On-device validation queue (not ranked; no effort estimates)

Code inspection can't prove these — verify on a device/simulator before acting:

1. **Camera-permission-denied behavior of the scanner.** `ScannerView` (`Views/Scanning/ScannerView.swift`) presents `VNDocumentCameraViewController` with no pre-flight `AVCaptureDevice.authorizationStatus` check; confirm what a denied user actually sees and whether guidance to Settings is needed.
2. **Khmer text-length resilience** in: onboarding language/currency cards, `TransactionSetupPrompt`'s trailing action pill (`TransactionSetupPrompt.swift:42-47` — fixed paddings + `Spacer(minLength: 8)`), `EventSummaryCard`, Pro-analytics chip rail.
3. **Resolved accent tint with the empty AccentColor asset** — confirm it renders as system blue in both light/dark before defining a brand color (P3-2).
4. **Dynamic Type XXL** on `DataConflictResolutionView` (size-based `appFont(size:)` scales, but card layouts may clip), the calculator keypad, and Home's summary card.
5. **Home summary card contrast** — `FinancialSummaryCards` white-on-`Color.accentColor` (`HomeView.swift:198-213`) at accent opacity variants.
6. **Notification permission timing** — journey (a) never prompts for notifications until the user finds Settings; consider whether a contextual prompt (e.g. after 3rd transaction) would beat the current silence. Needs product judgment + device testing.

---

## Route inventory (appendix)

Status: **full** = audited full-depth · **skim** = pattern-violations pass only (design settled or secondary) · **dead** = unreachable · **oos** = out of scope per plan.

**Roots & gates** — `QuaraMoneyApp` (entry; root ErrorService alert; theme) full · `SplashScreenView` (launch) skim · `OnboardingView` + `OnboardingIllustrations` (first run, `!isOnboardingCompleted`) full · `AppLockView` (`isAppLockEnabled`, scene-phase lock) full · `SyncConflictPresenter` → `DataConflictResolutionView` (first sign-in with dual data) full · `ContentView` (tab root, no-wallet gate) full.

**Home tab** — `HomeView`/`HomeContentView`/`DailyHeader`/`HomeTransactionRow` full · `FinancialSummaryCards`, `GlassPeriodSelector` (`MonthSelectionView.swift`) skim · `FilterSheetView`/`FilterSheetButton` skim · `UndoToast` (modifier, 5 call sites) skim.

**Transactions** — `AddTransactionContainer` (Home FAB/edit/backdate/largest-drilldown) full · `AddTransactionView` full · `CompactAddTransactionView` oos (settled experiment; scan finding P2-1 applies to it too) · `TransactionSetupPrompt` full · `TransactionListView`, `TransactionRowView` full · `FilteredTransactionsDetailView` skim · wallet/category picker sheets, `TransactionLocationPickerView` skim · `ScannerView` full.

**Analysis tab** — `AnalysisView` (entry surface) skim · `ProAnalyticsView`/`ProAnalyticsCharts`/`ProDashboardSheets` oos (settled 2026-06/07 redesign).

**Plan tab** — `BudgetTabView` full · `BudgetListView`, `AddBudgetView`, `EditBudgetView`, `BudgetDetailView`, `BudgetInsightsView` skim · `SavingsGoalListView` + row/summary/detail/add/edit skim (list entry checked full).

**More tab** — `MoreView` full · `AccountView` full (destructive flows) · `AuthSheetView` full · `ResetPasswordSheetView` skim · `AvatarCropView`, `ProfileAvatarView` skim · `CategoryListView`, `AddCategoryView` skim · `DebtListView`/`DebtDetailView`/`AddDebtView`/`DebtComponents` oos (settled) · `RecurringRuleListView`/`Detail`/`Editor`, `RecurringReviewView`, `RecurringProgressHeaderView` oos (settled 2026-06 rework; badge path in MoreView checked) · `EventListView` full · `EventDetailViewV2` full · `AddEventView`, `AddEventMemberView`, `AddEventLedgerTransactionView`, `EventSettlementView`, Events components skim · `SettingsView` full · `ThemeSettingsView`, `CurrencySelectionView` skim · `ReceiptScanningSettingsView` oos (settled) · `ExportOptionsView`, `CSVImportView` full.

**Wallets** — `AddWalletView` full (creation mode) · `WalletListView`, `WalletDetailView`, `WalletRowView`, `NetWorthCard`, `WalletSparkline`, `AdjustBalanceView`, `MoveTransactionsSheet` oos (settled redesign).

**Shared components** — `AmountDisplayView`, `CalculatorKeyboardView`, `CategoryGridItem`, `WalletGridItem`, `ColorPickerView`, `IconPickerView`, `ListIconView`, `MultiCategoryPicker`, `SelectableRow`, `FlowLayout`, `ShareSheet`, `LazyView` skim (as encountered in parents) · `NotificationCenterView`, `FilterMenuView`, `AppearancePickers.swift` **dead**.

**Non-view surfaces** — local notifications: `NotificationManager` (daily reminder), `BudgetNotificationService` (threshold alerts + daily summary), `BudgetRolloverService` (rollover), `RecurringNotificationService` (reminders) — audited, see P2-2 · deep links: `.openAddTransaction`/`.openRecurringReview`/`.openProAnalytics` staged via `AppRouter`, consumed visibility-gated in Home/More (audited — clean, no timer races) · auth callback URL (Supabase magic link/reset) skim · biometric prompt (`SecurityManager`) audited, see P2-2.

---

## Deferred (explicit)

- **Accessibility/VoiceOver audit** — deliberately excluded this cycle at the owner's direction. **Recommended as a separate pre-launch gate**: icon-only toolbar buttons largely carry `accessibilityLabel`s already, so the floor is decent, but no systematic pass has been done.
- Simulator/device verification of everything in the validation queue.
- Performance, sync internals, data integrity (prior audits).

## Suggested fix batch (if picking by value-per-effort)

1. P2-2 notification localization (S — the market differentiator)
2. P2-1 scan feedback (M — flagship feature trust)
3. P2-3 + P2-4 + P2-5 + P2-6 (all S — permission dead end, sign-out confirm, delete-all friction, wallet-sheet escape)
4. Dead-UI cleanup + P3-1/3/4 (S — one tidy PR)
5. P2-7 Events IA + P3-2 brand accent (needs a small design decision each)
