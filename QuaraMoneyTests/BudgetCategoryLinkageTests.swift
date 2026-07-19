import XCTest
import SwiftData
@testable import QuaraMoney

private typealias AppCategory = QuaraMoney.Category

@MainActor
final class BudgetCategoryLinkageTests: XCTestCase {
    private enum InjectedFailure: Error { case transientCategoryFetch }

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        container = TestModelContainer.create()
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Model representation and change detection

    func testSetTrackedCategoriesStoresSingleSelectionInJoinAndTotalClearsBoth() throws {
        let category = makeCategory("Food")
        let budget = makeBudget()

        budget.setTrackedCategories([category], targetKind: .categories)

        XCTAssertEqual(budget.categories?.map(\.id), [category.id])
        XCTAssertNil(budget.category)
        XCTAssertTrue(budget.categorySetDirty)

        budget.categorySetDirty = false
        budget.setTrackedCategories([], targetKind: .total)

        XCTAssertTrue(budget.categories?.isEmpty != false, "SwiftData may materialize a nil to-many as []")
        XCTAssertNil(budget.category)
        XCTAssertEqual(budget.targetKind, .total)
        XCTAssertTrue(budget.categorySetDirty)
        try context.save()
    }

    func testTwoBudgetsRetainSharedJoinCategory() throws {
        let category = makeCategory("Food")
        let first = makeBudget()
        let second = makeBudget()

        first.setTrackedCategories([category], targetKind: .categories)
        second.setTrackedCategories([category], targetKind: .categories)
        try context.save()

        XCTAssertEqual(first.effectiveTrackedCategories.map(\.id), [category.id])
        XCTAssertEqual(second.effectiveTrackedCategories.map(\.id), [category.id])
        XCTAssertEqual(category.multiCategoryBudgets?.count, 2)
    }

    func testEffectiveTrackedCategoriesUnionsScalarAndJoinByUUIDAndFiltersTombstones() {
        let scalar = makeCategory("Scalar")
        let joined = makeCategory("Joined")
        let tombstoned = makeCategory("Deleted")
        tombstoned.deletedAt = Date()
        let budget = makeBudget()

        budget.category = scalar
        XCTAssertEqual(budget.effectiveTrackedCategories.map(\.id), [scalar.id])

        budget.categories = [joined, scalar, joined, tombstoned]
        let expected = [scalar.id, joined.id].sorted { $0.uuidString < $1.uuidString }
        XCTAssertEqual(budget.effectiveTrackedCategories.map(\.id), expected)
        XCTAssertEqual(budget.trackedCategoryIds, expected)
        XCTAssertEqual(budget.trackedCategoryInfos.map(\.id), expected)
    }

    func testSetTrackedCategoriesOnlyFlagsRealNormalizedChanges() {
        let first = makeCategory("First")
        let second = makeCategory("Second")
        let budget = makeBudget()
        budget.setTrackedCategories([first, second], targetKind: .categories)

        budget.categorySetDirty = false
        budget.setTrackedCategories([second, first, first], targetKind: .categories)
        XCTAssertFalse(budget.categorySetDirty, "Same UUID set and target kind is a no-op")

        budget.setTrackedCategories([first], targetKind: .categories)
        XCTAssertTrue(budget.categorySetDirty, "Removing a category is real intent")

        budget.categorySetDirty = false
        budget.setTrackedCategories([first, second], targetKind: .categories)
        XCTAssertTrue(budget.categorySetDirty, "Adding a category is real intent")

        budget.categorySetDirty = false
        budget.setTrackedCategories([], targetKind: .total)
        XCTAssertTrue(budget.categorySetDirty, "Changing target kind is real intent")
    }

    // MARK: - Pull precedence matrix

    func testPullPrecedenceTotalClearsLocalSet() {
        let local = makeCategory("Local")
        let budget = cleanCategoryBudget([local])

        let result = SyncEngine.applySyncedTrackedCategories(
            cloudCategoryIDs: [],
            resolvedCategoriesByID: [:],
            targetKind: .total,
            to: budget
        )

        XCTAssertEqual(result.action, .totalCleared)
        XCTAssertEqual(budget.targetKind, .total)
        XCTAssertTrue(budget.effectiveTrackedCategories.isEmpty)
        XCTAssertFalse(budget.categorySetDirty)
    }

    func testPullPrecedenceAllLiveAppliesCloudAndClearsDirty() {
        let local = makeCategory("Local")
        let cloudA = makeCategory("Cloud A")
        let cloudB = makeCategory("Cloud B")
        let budget = cleanCategoryBudget([local])

        let result = SyncEngine.applySyncedTrackedCategories(
            cloudCategoryIDs: [cloudA.id, cloudB.id],
            resolvedCategoriesByID: [cloudA.id: cloudA, cloudB.id: cloudB],
            targetKind: .categories,
            to: budget
        )

        XCTAssertEqual(result.action, .cloudApplied)
        XCTAssertEqual(Set(budget.trackedCategoryIds), [cloudA.id, cloudB.id])
        XCTAssertNil(budget.category)
        XCTAssertFalse(budget.categorySetDirty)
    }

    func testPullPrecedenceAnyAbsentPreservesLocalWithoutDirtying() {
        let local = makeCategory("Local")
        let cloud = makeCategory("Cloud")
        let absentID = UUID()
        let budget = cleanCategoryBudget([local])

        let result = SyncEngine.applySyncedTrackedCategories(
            cloudCategoryIDs: [cloud.id, absentID],
            resolvedCategoriesByID: [cloud.id: cloud],
            targetKind: .categories,
            to: budget
        )

        XCTAssertEqual(result.action, .incompletePreserved)
        XCTAssertEqual(result.absentCount, 1)
        XCTAssertEqual(budget.trackedCategoryIds, [local.id])
        XCTAssertFalse(budget.categorySetDirty)
    }

    func testPullPrecedenceAllTombstonedNonEmptyCloudSetClearsLocal() {
        let local = makeCategory("Local")
        let tombstoned = makeCategory("Deleted")
        tombstoned.deletedAt = Date()
        let budget = cleanCategoryBudget([local])

        let result = SyncEngine.applySyncedTrackedCategories(
            cloudCategoryIDs: [tombstoned.id],
            resolvedCategoriesByID: [tombstoned.id: tombstoned],
            targetKind: .categories,
            to: budget
        )

        XCTAssertEqual(result.action, .cloudApplied)
        XCTAssertEqual(result.tombstonedCount, 1)
        XCTAssertTrue(budget.effectiveTrackedCategories.isEmpty)
        XCTAssertFalse(budget.categorySetDirty)
    }

    func testPullPrecedenceEmptyCloudRepairsFromLocalAndQueuesPush() {
        let local = makeCategory("Local")
        let budget = cleanCategoryBudget([local])
        budget.needsSync = false
        let repairTime = Date(timeIntervalSince1970: 20_000)

        let result = SyncEngine.applySyncedTrackedCategories(
            cloudCategoryIDs: [],
            resolvedCategoriesByID: [:],
            targetKind: .categories,
            to: budget,
            repairTimestamp: repairTime
        )

        XCTAssertEqual(result.action, .emptyRepaired)
        XCTAssertEqual(budget.trackedCategoryIds, [local.id])
        XCTAssertTrue(budget.categorySetDirty)
        XCTAssertTrue(budget.needsSync)
        XCTAssertEqual(budget.updatedAt, repairTime)
    }

    // MARK: - Parent/category decoupling and push shaping

    func testNameOnlyBudgetFormSaveKeepsCategoryCleanThenCloudHealsWithoutJoinRebuild() {
        let owner = UUID()
        let local = makeCategory("Local")
        let cloudB = makeCategory("Cloud B")
        let cloudC = makeCategory("Cloud C")
        let budget = cleanCategoryBudget([local])
        let remoteTime = Date(timeIntervalSince1970: 10_000)
        let localEditTime = remoteTime.addingTimeInterval(60)
        budget.name = "Before"
        budget.needsSync = false
        budget.updatedAt = remoteTime

        // This is the same helper invoked by BudgetFormView.save(); it still
        // unconditionally re-passes the form's seeded category selection.
        BudgetFormView.applyFormValues(
            to: budget,
            name: "Renamed locally",
            amount: budget.amountLimit,
            currencyCode: budget.currencyCode,
            selectedCategories: [local],
            targetKind: .categories,
            periodType: budget.periodType,
            customStart: budget.startDate,
            customEnd: budget.customEndDate ?? budget.startDate,
            alertMode: budget.alertMode,
            isNewBudget: false,
            now: localEditTime
        )

        XCTAssertFalse(budget.categorySetDirty, "A name-only form save must not claim category intent")
        XCTAssertTrue(budget.needsSync)

        let row = makeBudgetRow(
            id: budget.id,
            ownerID: owner,
            name: "Older cloud name",
            updatedAt: remoteTime,
            targetKind: .categories
        )
        let result = SyncEngine.applySyncedBudgetRow(
            row,
            cloudCategoryIDs: [local.id, cloudB.id, cloudC.id],
            resolvedCategoriesByID: [local.id: local, cloudB.id: cloudB, cloudC.id: cloudC],
            to: budget
        )

        XCTAssertTrue(result.parentLocalWins)
        XCTAssertEqual(budget.name, "Renamed locally")
        XCTAssertEqual(Set(budget.trackedCategoryIds), [local.id, cloudB.id, cloudC.id])
        XCTAssertFalse(budget.categorySetDirty)
        XCTAssertTrue(budget.needsSync, "The newer parent edit must still push")

        let push = try! XCTUnwrap(SyncEngine.makeBudgetPushSnapshots([budget], userID: owner).first)
        XCTAssertNil(push.parentDTO.category_id)
        XCTAssertFalse(push.categorySetDirty)
        XCTAssertTrue([push].filter(\.categorySetDirty).isEmpty, "Parent-only push must not rebuild cloud joins")
    }

    func testParentLocalWinsPreservesSoftDeleteWhileCloudCategorySetStillHeals() {
        let owner = UUID()
        let local = makeCategory("Local")
        let cloud = makeCategory("Cloud")
        let budget = cleanCategoryBudget([local])
        let remoteTime = Date(timeIntervalSince1970: 10_000)
        let localDeleteTime = remoteTime.addingTimeInterval(60)
        budget.deletedAt = localDeleteTime
        budget.updatedAt = localDeleteTime
        budget.needsSync = true

        let row = makeBudgetRow(
            id: budget.id,
            ownerID: owner,
            name: "Older cloud name",
            updatedAt: remoteTime,
            targetKind: .categories
        )
        let result = SyncEngine.applySyncedBudgetRow(
            row,
            cloudCategoryIDs: [cloud.id],
            resolvedCategoriesByID: [cloud.id: cloud],
            to: budget
        )

        XCTAssertTrue(result.parentLocalWins)
        XCTAssertEqual(budget.deletedAt, localDeleteTime)
        XCTAssertEqual(budget.trackedCategoryIds, [cloud.id])
        XCTAssertFalse(budget.categorySetDirty)
        XCTAssertTrue(budget.needsSync)
    }

    func testDirtyLocalCategorySetIgnoresCloudAndPushSnapshotRebuildsThenClearsIntent() throws {
        let owner = UUID()
        let local = makeCategory("Local")
        let cloud = makeCategory("Cloud")
        let budget = makeBudget()
        budget.setTrackedCategories([local], targetKind: .categories)
        budget.needsSync = true
        context.insert(budget)
        try context.save()

        let result = SyncEngine.applySyncedTrackedCategories(
            cloudCategoryIDs: [cloud.id],
            resolvedCategoriesByID: [cloud.id: cloud],
            targetKind: .categories,
            to: budget
        )
        XCTAssertEqual(result.action, .localDirtyPreserved)
        XCTAssertEqual(budget.trackedCategoryIds, [local.id])

        let snapshot = try XCTUnwrap(SyncEngine.makeBudgetPushSnapshots([budget], userID: owner).first)
        XCTAssertTrue(snapshot.categorySetDirty)
        XCTAssertEqual(snapshot.joinRows(userID: owner).map(\.category_id), [local.id])
        XCTAssertNil(snapshot.parentDTO.category_id)

        var returned = snapshot.parentDTO
        returned.updated_at = budget.updatedAt.addingTimeInterval(1)
        SyncEngine.shared.finishBudgetPush(
            [returned],
            pending: [budget],
            snapshots: [snapshot],
            rebuiltBudgetIDs: [budget.id],
            uid: owner,
            context: context
        )
        XCTAssertFalse(budget.categorySetDirty)
        XCTAssertFalse(budget.needsSync)
    }

    func testScalarFallbackPushShapesOneJoinAndNullParentCategory() throws {
        let owner = UUID()
        let scalar = makeCategory("Legacy")
        let budget = Budget(amountLimit: 100, currencyCode: "USD", category: scalar, month: 7, year: 2026)
        budget.categorySetDirty = true
        context.insert(budget)

        let snapshot = try XCTUnwrap(SyncEngine.makeBudgetPushSnapshots([budget], userID: owner).first)
        XCTAssertEqual(snapshot.categoryIDs, [scalar.id])
        XCTAssertEqual(snapshot.joinRows(userID: owner).map(\.category_id), [scalar.id])
        XCTAssertNil(snapshot.parentDTO.category_id)
    }

    func testParentOnlyDirtyBudgetDoesNotPlanJoinRebuild() throws {
        let owner = UUID()
        let category = makeCategory("Food")
        let budget = cleanCategoryBudget([category])
        budget.name = "Parent edit"
        budget.needsSync = true
        budget.categorySetDirty = false

        let snapshot = try XCTUnwrap(SyncEngine.makeBudgetPushSnapshots([budget], userID: owner).first)
        XCTAssertFalse(snapshot.categorySetDirty)
        XCTAssertNil(snapshot.parentDTO.category_id)
        XCTAssertTrue([snapshot].filter(\.categorySetDirty).isEmpty)
    }

    // MARK: - One-time reconciliation and keep-local

    func testSelfHealResetsAdvancedCursorAndRestoresCloudThreeCategorySet() throws {
        let owner = UUID()
        let suiteName = "BudgetCategorySelfHeal.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(99_999.0, forKey: SyncEngine.cursorKey("budgets"))

        XCTAssertTrue(SyncEngine.prepareBudgetCategoryReconciliation(ownerID: owner, defaults: defaults))
        XCTAssertNil(defaults.object(forKey: SyncEngine.cursorKey("budgets")))
        XCTAssertFalse(defaults.bool(forKey: PlanDataMaintenance.budgetCategoryReconciliationMarkerKey(ownerID: owner)))

        let local = makeCategory("Local")
        let cloudB = makeCategory("Cloud B")
        let cloudC = makeCategory("Cloud C")
        let budget = cleanCategoryBudget([local])
        budget.needsSync = false
        budget.syncUserID = owner
        let row = makeBudgetRow(
            id: budget.id,
            ownerID: owner,
            name: "Cloud",
            updatedAt: Date(timeIntervalSince1970: 30_000),
            targetKind: .categories
        )

        SyncEngine.applySyncedBudgetRow(
            row,
            cloudCategoryIDs: [local.id, cloudB.id, cloudC.id],
            resolvedCategoriesByID: [local.id: local, cloudB.id: cloudB, cloudC.id: cloudC],
            to: budget
        )

        XCTAssertEqual(Set(budget.trackedCategoryIds), [local.id, cloudB.id, cloudC.id])
        XCTAssertFalse(budget.categorySetDirty)
        PlanDataMaintenance.commitBudgetCategoryReconciliation(ownerID: owner, defaults: defaults)
        XCTAssertFalse(SyncEngine.prepareBudgetCategoryReconciliation(ownerID: owner, defaults: defaults))
    }

    func testReconciliationFlagsOnlyLocalOnlyBudgetAndShapesFirstJoinUpload() throws {
        let owner = UUID()
        let category = makeCategory("Legacy")
        let localOnly = Budget(amountLimit: 100, currencyCode: "USD", category: category, month: 7, year: 2026)
        localOnly.needsSync = false
        localOnly.categorySetDirty = false
        let cloudOwned = makeBudget()
        cloudOwned.setTrackedCategories([category], targetKind: .categories)
        cloudOwned.syncUserID = owner
        cloudOwned.needsSync = true
        cloudOwned.categorySetDirty = false
        context.insert(localOnly)
        try context.save()

        let count = try SyncEngine.flagLocalOnlyBudgetCategorySets(
            context: context,
            cloudBudgetIDs: [cloudOwned.id],
            ownerID: owner
        )

        XCTAssertEqual(count, 1)
        XCTAssertTrue(localOnly.categorySetDirty)
        XCTAssertTrue(localOnly.needsSync)
        XCTAssertFalse(cloudOwned.categorySetDirty, "Cloud-owned parent dirtiness is not category intent")
        let upload = try XCTUnwrap(SyncEngine.makeBudgetPushSnapshots([localOnly], userID: owner).first)
        XCTAssertEqual(upload.joinRows(userID: owner).map(\.category_id), [category.id])
    }

    func testKeepLocalFlagsEveryBudgetCategorySetForRepublish() throws {
        let owner = UUID()
        let category = makeCategory("Food")
        let budget = cleanCategoryBudget([category])
        budget.needsSync = false
        budget.categorySetDirty = false
        try context.save()

        SyncEngine.shared.forceAllLocalNeedsSync(context: context)

        XCTAssertTrue(budget.needsSync)
        XCTAssertTrue(budget.categorySetDirty)
        let snapshot = try XCTUnwrap(SyncEngine.makeBudgetPushSnapshots([budget], userID: owner).first)
        XCTAssertTrue(snapshot.categorySetDirty)
        XCTAssertEqual(snapshot.joinRows(userID: owner).map(\.category_id), [category.id])
    }

    // MARK: - Injected pull failure and recovery

    func testTransientReferencedCategoryFetchFailureDoesNotAdvanceCursorAndRecoveryKeepsParentJoinDecoupled() async throws {
        let owner = UUID()
        let local = makeCategory("Local")
        let cloudB = AppCategory(name: "Cloud B", icon: "bag", colorHex: "#222222", type: .expense)
        let cloudC = AppCategory(name: "Cloud C", icon: "bag", colorHex: "#333333", type: .expense)
        let budget = cleanCategoryBudget([local])
        let remoteTime = Date(timeIntervalSince1970: 50_000)
        let localTime = remoteTime.addingTimeInterval(60)
        budget.name = "Concurrent local name"
        budget.updatedAt = localTime
        budget.needsSync = true
        budget.categorySetDirty = false
        try context.save()

        let row = makeBudgetRow(
            id: budget.id,
            ownerID: owner,
            name: "Cloud name",
            updatedAt: remoteTime,
            targetKind: .categories
        )
        let joins = [local.id, cloudB.id, cloudC.id].map {
            SyncBudgetCategoryRow(budget_id: budget.id, category_id: $0, user_id: owner)
        }
        let cursorKey = SyncEngine.cursorKey("budgets")
        let savedCursor = UserDefaults.standard.object(forKey: cursorKey)
        defer {
            if let savedCursor { UserDefaults.standard.set(savedCursor, forKey: cursorKey) }
            else { UserDefaults.standard.removeObject(forKey: cursorKey) }
        }
        UserDefaults.standard.set(remoteTime.addingTimeInterval(-100).timeIntervalSince1970, forKey: cursorKey)
        let cursorBeforeFailure = UserDefaults.standard.double(forKey: cursorKey)

        do {
            _ = try await SyncEngine.shared.pullBudgetRows(
                [row],
                context: context,
                ownerID: owner,
                fetchJoinRows: { _ in joins },
                fetchCategoryRows: { _ in throw InjectedFailure.transientCategoryFetch }
            )
            XCTFail("Expected the injected category fetch failure")
        } catch InjectedFailure.transientCategoryFetch {
            // Expected.
        }

        XCTAssertEqual(UserDefaults.standard.double(forKey: cursorKey), cursorBeforeFailure)
        XCTAssertEqual(budget.name, "Concurrent local name")
        XCTAssertEqual(budget.trackedCategoryIds, [local.id])
        XCTAssertFalse(budget.categorySetDirty)
        XCTAssertFalse(
            try XCTUnwrap(SyncEngine.makeBudgetPushSnapshots([budget], userID: owner).first).categorySetDirty,
            "A concurrent parent edit must not publish stale joins after pull failure"
        )

        _ = try await SyncEngine.shared.pullBudgetRows(
            [row],
            context: context,
            ownerID: owner,
            fetchJoinRows: { _ in joins },
            fetchCategoryRows: { requestedIDs in
                XCTAssertEqual(Set(requestedIDs), [cloudB.id, cloudC.id])
                return [
                    self.makeCategoryRow(cloudB, ownerID: owner, updatedAt: remoteTime),
                    self.makeCategoryRow(cloudC, ownerID: owner, updatedAt: remoteTime)
                ]
            }
        )

        XCTAssertEqual(budget.name, "Concurrent local name")
        XCTAssertEqual(Set(budget.trackedCategoryIds), [local.id, cloudB.id, cloudC.id])
        XCTAssertFalse(budget.categorySetDirty)
        XCTAssertTrue(budget.needsSync)
        XCTAssertEqual(UserDefaults.standard.double(forKey: cursorKey), remoteTime.timeIntervalSince1970)
        XCTAssertFalse(try XCTUnwrap(SyncEngine.makeBudgetPushSnapshots([budget], userID: owner).first).categorySetDirty)
    }

    // MARK: - Fixtures

    private func makeCategory(_ name: String) -> AppCategory {
        let category = AppCategory(name: name, icon: "bag", colorHex: "#111111", type: .expense)
        context.insert(category)
        return category
    }

    private func makeBudget() -> Budget {
        let budget = Budget(amountLimit: 100)
        context.insert(budget)
        return budget
    }

    private func cleanCategoryBudget(_ categories: [AppCategory]) -> Budget {
        let budget = makeBudget()
        budget.setTrackedCategories(categories, targetKind: .categories)
        budget.categorySetDirty = false
        return budget
    }

    private func makeBudgetRow(
        id: UUID,
        ownerID: UUID,
        name: String?,
        updatedAt: Date,
        targetKind: BudgetTargetKind,
        categoryID: UUID? = nil
    ) -> SyncBudgetRow {
        SyncBudgetRow(
            id: id,
            user_id: ownerID,
            name: name,
            amount_limit: 100,
            currency_code: "USD",
            period_type_raw: BudgetPeriodType.monthly.rawValue,
            start_date: Date(timeIntervalSince1970: 1_000),
            created_at: Date(timeIntervalSince1970: 500),
            updated_at: updatedAt,
            custom_end_date: nil,
            month: 7,
            year: 2026,
            is_recurring: true,
            rollover_excess: false,
            rollover_amount: 0,
            amount_type_data: nil,
            alert_at_50: false,
            alert_at_80: true,
            alert_at_100: true,
            alert_on_projected_overspend: false,
            last_alert_triggered_date: nil,
            last_alert_threshold: 0,
            budget_category_type_raw: nil,
            category_id: categoryID,
            target_kind: targetKind.rawValue,
            alert_mode: BudgetAlertMode.nearingOver.rawValue,
            last_alert_period_key: nil,
            week_start_day: nil,
            deleted_at: nil
        )
    }

    private func makeCategoryRow(
        _ category: AppCategory,
        ownerID: UUID,
        updatedAt: Date
    ) -> SyncCategoryRow {
        SyncCategoryRow(
            id: category.id,
            user_id: ownerID,
            name: category.name,
            icon: category.icon,
            color_hex: category.colorHex,
            type: category.type.rawValue,
            is_system: category.isSystem,
            canonical_key: category.canonicalKey,
            created_at: category.createdAt,
            updated_at: updatedAt,
            deleted_at: category.deletedAt
        )
    }
}
