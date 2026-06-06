import SwiftUI
import SwiftUI
import SwiftData

struct DebtListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Debt.dateCreated, order: .reverse) private var allDebts: [Debt]

    @State private var viewModel = DebtListViewModel()

    @State private var showAddDebtSheet = false
    @State private var debtToEdit: Debt?
    @State private var debtToDelete: Debt?
    @State private var showingDeleteAlert = false

    private var isFilterActive: Bool {
        viewModel.showCompleted
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SummaryCard(title: L10n.Debt.iOwe, amount: viewModel.totalIOwe(allDebts), color: .red, icon: "arrow.down.circle.fill")
                SummaryCard(title: L10n.Debt.owedToMe, amount: viewModel.totalOwedToMe(allDebts), color: .green, icon: "arrow.up.circle.fill")
            }
            .padding()

            Picker("Filter", selection: $viewModel.selectedType) {
                Text(L10n.DebtAdditional.filterAll).tag(Optional<DebtType>.none)
                ForEach(DebtType.allCases) { type in
                    Text(type.title).tag(Optional(type))
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom)

            if viewModel.filteredDebts(allDebts).isEmpty {
                ContentUnavailableView(L10n.DebtAdditional.noDebts, systemImage: "signature", description: Text(L10n.DebtAdditional.noDebtsDescription))
            } else {
                List {
                    Section {
                        ForEach(viewModel.activeDebts(allDebts)) { debt in
                            NavigationLink(destination: DebtDetailView(debt: debt)) {
                                DebtRow(debt: debt)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    debtToDelete = debt
                                    showingDeleteAlert = true
                                } label: {
                                    Label(L10n.Common.delete, systemImage: "trash")
                                }

                                Button {
                                    debtToEdit = debt
                                } label: {
                                    Label(L10n.Common.edit, systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        if !viewModel.activeDebts(allDebts).isEmpty {
                            Text(L10n.DebtAdditional.filterActive)
                        }
                    }

                    if viewModel.showCompleted {
                        Section {
                            ForEach(viewModel.completedDebts(allDebts)) { debt in
                                NavigationLink(destination: DebtDetailView(debt: debt)) {
                                    DebtRow(debt: debt)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        debtToDelete = debt
                                        showingDeleteAlert = true
                                    } label: {
                                        Label(L10n.Common.delete, systemImage: "trash")
                                    }

                                    Button {
                                        debtToEdit = debt
                                    } label: {
                                        Label(L10n.Common.edit, systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                        } header: {
                            Text(L10n.DebtAdditional.filterCompleted)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(L10n.Debt.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showAddDebtSheet = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add debt")
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show Completed", isOn: $viewModel.showCompleted)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .appFont(size: 14, weight: .semibold)
                        .foregroundStyle(isFilterActive ? .white : .primary)
                        .padding(6)
                        .background {
                            if isFilterActive {
                                Circle()
                                    .fill(.blue)
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showAddDebtSheet) {
            AddDebtView()
        }
        .sheet(item: $debtToEdit) { debt in
            AddDebtView(debtToEdit: debt)
        }
        .alert(L10n.Common.delete, isPresented: $showingDeleteAlert, presenting: debtToDelete) { debt in
            Button(L10n.Common.cancel, role: .cancel) {}
            Button(L10n.Common.delete, role: .destructive) {
                viewModel.deleteDebt(debt, context: modelContext)
            }
        } message: { debt in
            Text(L10n.Debt.deleteRelatedTransactionsWarning(viewModel.linkedTransactionCount(debt)))
        }
        .onAppear {
            normalizeCompletionStates()
        }
        .onChange(of: allDebts.count) { _, _ in
            normalizeCompletionStates()
        }
    }
    
    private func normalizeCompletionStates() {
        let tolerance: Decimal = 0.000001
        var didChange = false
        
        for debt in allDebts {
            let shouldBeCompleted = debt.remainingAmount <= tolerance
            if debt.isCompleted != shouldBeCompleted {
                debt.isCompleted = shouldBeCompleted
                didChange = true
            }
        }
        
        if didChange {
            do {
                try modelContext.save()
            } catch {
                ErrorService.shared.handlePersistenceError(error, context: "DebtListView.normalizeCompletionStates")
            }
            NotificationCenter.default.post(name: .dataDidUpdate, object: nil)
        }
    }
}

struct DebtRow: View {
    let debt: Debt
    
    var body: some View {
        HStack {
            // Icon
            ZStack {
                Circle()
                    .fill((debt.type == .owedToMe ? Color.green : Color.red).opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: debt.type == .owedToMe ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.app(.body))
                    .foregroundStyle(debt.type == .owedToMe ? .green : .red)
            }

            VStack(alignment: .leading) {
                Text(debt.personName)
                    .font(.app(.body, weight: .medium))

                if let note = debt.note, !note.isEmpty {
                    Text(note)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                } else {
                    Text(debt.type.title)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(debt.remainingAmount.formattedAmount(for: debt.currencyCode))
                    .font(.app(.body, weight: .semibold))
                    .foregroundStyle(debt.type == .owedToMe ? .green : .red)

                if debt.isCompleted {
                    Text(L10n.Debt.paid)
                        .font(.app(.caption2))
                        .foregroundStyle(.green)
                } else {
                    if let dueDate = debt.dueDate {
                        Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.app(.caption2))
                            .foregroundStyle(dueDate < Date() ? .red : .secondary)
                    } else {
                        Text(debt.dateCreated.formatted(date: .abbreviated, time: .omitted))
                            .font(.app(.caption2))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(debt.personName), \(debt.type == .owedToMe ? "owes you" : "you owe") \(debt.remainingAmount.formattedAmount(for: debt.currencyCode))\(debt.isCompleted ? ", paid" : "")")
    }
}

struct SummaryCard: View {
    let title: String
    let amount: Decimal
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(amount, format: .currency(code: CurrencyManager.shared.preferredCurrencyCode))
                .font(.headline)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(amount.formatted(.currency(code: CurrencyManager.shared.preferredCurrencyCode)))")
    }
}
