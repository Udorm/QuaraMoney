import SwiftUI
import SwiftData

/// View for managing category groups
struct CategoryGroupListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CategoryGroup.name) private var groups: [CategoryGroup]
    
    @State private var showAddGroup = false
    
    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView(
                    "No Category Groups",
                    systemImage: "folder.fill.badge.gearshape",
                    description: Text("Create groups to organize related categories together for easier budgeting.")
                )
            } else {
                List {
                    ForEach(groups) { group in
                        NavigationLink {
                            CategoryGroupDetailView(group: group)
                        } label: {
                            CategoryGroupRowView(group: group)
                        }
                    }
                    .onDelete(perform: deleteGroups)
                }
            }
        }
        .navigationTitle("Category Groups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddGroup = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddGroup) {
            AddCategoryGroupView()
        }
    }
    
    private func deleteGroups(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(groups[index])
            }
        }
    }
}

// MARK: - Category Group Row View

struct CategoryGroupRowView: View {
    let group: CategoryGroup
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: group.iconName)
                .font(.title2)
                .foregroundStyle(Color(hex: group.colorHex) ?? .blue)
                .frame(width: 44, height: 44)
                .background((Color(hex: group.colorHex) ?? .blue).opacity(0.15))
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.headline)
                
                HStack(spacing: 8) {
                    Text("\(group.categoryCount) categories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if let budgetType = group.budgetCategoryType {
                        Text(budgetType.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: budgetType.color)?.opacity(0.2) ?? Color.gray.opacity(0.2))
                            .foregroundStyle(Color(hex: budgetType.color) ?? .gray)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Category Group View

struct AddCategoryGroupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Category.name) private var categories: [Category]
    
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedIcon: String = "folder.fill"
    @State private var selectedColor: String = "#6B7280"
    @State private var budgetCategoryType: BudgetCategoryType?
    @State private var selectedCategories: Set<UUID> = []
    
    @State private var showIconPicker = false
    @State private var showColorPicker = false
    
    private var isFormValid: Bool {
        !name.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                Section("Group Info") {
                    TextField("Group Name", text: $name)
                    
                    TextField("Description (Optional)", text: $description)
                }
                
                // Appearance
                Section("Appearance") {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text("Icon")
                            Spacer()
                            Image(systemName: selectedIcon)
                                .foregroundStyle(Color(hex: selectedColor) ?? .gray)
                        }
                    }
                    
                    Button {
                        showColorPicker = true
                    } label: {
                        HStack {
                            Text("Color")
                            Spacer()
                            Circle()
                                .fill(Color(hex: selectedColor) ?? .gray)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                
                // Budget Category Type
                Section {
                    Picker("Budget Type", selection: $budgetCategoryType) {
                        Text("None").tag(nil as BudgetCategoryType?)
                        ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type as BudgetCategoryType?)
                        }
                    }
                } header: {
                    Text("Categorization")
                } footer: {
                    Text("Helps organize groups for template-based budgeting")
                }
                
                // Categories
                Section {
                    if categories.filter({ $0.type == .expense }).isEmpty {
                        Text("No expense categories available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(categories.filter { $0.type == .expense }) { category in
                            Button {
                                toggleCategory(category)
                            } label: {
                                HStack {
                                    Image(systemName: category.icon)
                                        .foregroundStyle(Color(hex: category.colorHex) ?? .gray)
                                        .frame(width: 30)
                                    
                                    Text(category.name)
                                        .foregroundStyle(.primary)
                                    
                                    Spacer()
                                    
                                    if selectedCategories.contains(category.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Categories (\(selectedCategories.count) selected)")
                }
                
                // Quick Templates
                Section("Quick Templates") {
                    ForEach(PredefinedCategoryGroup.allCases, id: \.self) { template in
                        Button {
                            applyTemplate(template)
                        } label: {
                            HStack {
                                Image(systemName: template.icon)
                                    .foregroundStyle(Color(hex: template.color) ?? .gray)
                                    .frame(width: 30)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.displayName)
                                        .foregroundStyle(.primary)
                                    Text(template.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Category Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createGroup()
                        dismiss()
                    }
                    .disabled(!isFormValid)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon, selectedColorHex: $selectedColor)
            }
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColorHex: $selectedColor)
            }
        }
    }
    
    private func toggleCategory(_ category: Category) {
        if selectedCategories.contains(category.id) {
            selectedCategories.remove(category.id)
        } else {
            selectedCategories.insert(category.id)
        }
    }
    
    private func applyTemplate(_ template: PredefinedCategoryGroup) {
        name = template.displayName
        selectedIcon = template.icon
        selectedColor = template.color
        budgetCategoryType = template.budgetCategoryType
        description = template.description
        
        // Match categories by name
        selectedCategories = Set(categories.filter { category in
            template.suggestedCategories.contains { suggested in
                category.name.lowercased().contains(suggested.lowercased())
            }
        }.map { $0.id })
    }
    
    private func createGroup() {
        let group = CategoryGroup(
            name: name,
            iconName: selectedIcon,
            colorHex: selectedColor,
            budgetCategoryType: budgetCategoryType
        )
        
        group.groupDescription = description.isEmpty ? nil : description
        
        // Add selected categories
        for categoryId in selectedCategories {
            if let category = categories.first(where: { $0.id == categoryId }) {
                group.addCategory(category)
            }
        }
        
        modelContext.insert(group)
    }
}

// MARK: - Category Group Detail View

struct CategoryGroupDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var group: CategoryGroup
    
    @Query(sort: \Category.name) private var allCategories: [Category]
    @Query private var budgets: [Budget]
    
    @State private var showEditGroup = false
    @State private var showAddCategories = false
    
    private var linkedBudgets: [Budget] {
        budgets.filter { $0.categoryGroup?.id == group.id }
    }
    
    var body: some View {
        List {
            // Header Section
            Section {
                VStack(spacing: 16) {
                    Image(systemName: group.iconName)
                        .font(.system(size: 48))
                        .foregroundStyle(Color(hex: group.colorHex) ?? .blue)
                    
                    VStack(spacing: 4) {
                        Text(group.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let description = group.groupDescription {
                            Text(description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        if let budgetType = group.budgetCategoryType {
                            HStack(spacing: 4) {
                                Image(systemName: budgetType.icon)
                                Text(budgetType.displayName)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(hex: budgetType.color)?.opacity(0.2) ?? Color.gray.opacity(0.2))
                            .foregroundStyle(Color(hex: budgetType.color) ?? .gray)
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .listRowBackground(Color.clear)
            
            // Categories Section
            Section {
                if group.categories.isEmpty {
                    Text("No categories in this group")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(group.categories) { category in
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundStyle(Color(hex: category.colorHex) ?? .gray)
                                .frame(width: 30)
                            
                            Text(category.name)
                            
                            Spacer()
                        }
                    }
                    .onDelete(perform: removeCategories)
                }
                
                Button {
                    showAddCategories = true
                } label: {
                    Label("Add Categories", systemImage: "plus.circle")
                }
            } header: {
                Text("Categories (\(group.categoryCount))")
            }
            
            // Linked Budgets
            if !linkedBudgets.isEmpty {
                Section("Linked Budgets") {
                    ForEach(linkedBudgets) { budget in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(budget.displayName)
                                    .font(.subheadline)
                                Text(budget.periodDisplayString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Text(budget.amountLimit.formatted(.currency(code: budget.currencyCode)))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Group Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showEditGroup = true
                }
            }
        }
        .sheet(isPresented: $showEditGroup) {
            EditCategoryGroupView(group: group)
        }
        .sheet(isPresented: $showAddCategories) {
            AddCategoriesToGroupSheet(group: group, allCategories: allCategories.filter { $0.type == .expense })
        }
    }
    
    private func removeCategories(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                group.removeCategory(group.categories[index])
            }
        }
    }
}

// MARK: - Edit Category Group View

struct EditCategoryGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var group: CategoryGroup
    
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedIcon: String = ""
    @State private var selectedColor: String = ""
    @State private var budgetCategoryType: BudgetCategoryType?
    
    @State private var showIconPicker = false
    @State private var showColorPicker = false
    
    init(group: CategoryGroup) {
        self.group = group
        _name = State(initialValue: group.name)
        _description = State(initialValue: group.groupDescription ?? "")
        _selectedIcon = State(initialValue: group.iconName)
        _selectedColor = State(initialValue: group.colorHex)
        _budgetCategoryType = State(initialValue: group.budgetCategoryType)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Group Info") {
                    TextField("Group Name", text: $name)
                    TextField("Description (Optional)", text: $description)
                }
                
                Section("Appearance") {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Text("Icon")
                            Spacer()
                            Image(systemName: selectedIcon)
                                .foregroundStyle(Color(hex: selectedColor) ?? .gray)
                        }
                    }
                    
                    Button {
                        showColorPicker = true
                    } label: {
                        HStack {
                            Text("Color")
                            Spacer()
                            Circle()
                                .fill(Color(hex: selectedColor) ?? .gray)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                
                Section("Categorization") {
                    Picker("Budget Type", selection: $budgetCategoryType) {
                        Text("None").tag(nil as BudgetCategoryType?)
                        ForEach(BudgetCategoryType.allCases, id: \.self) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type as BudgetCategoryType?)
                        }
                    }
                }
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerView(selectedIcon: $selectedIcon, selectedColorHex: $selectedColor)
            }
            .sheet(isPresented: $showColorPicker) {
                ColorPickerView(selectedColorHex: $selectedColor)
            }
        }
    }
    
    private func saveChanges() {
        group.name = name
        group.groupDescription = description.isEmpty ? nil : description
        group.iconName = selectedIcon
        group.colorHex = selectedColor
        group.budgetCategoryType = budgetCategoryType
    }
}

// MARK: - Add Categories to Group Sheet

struct AddCategoriesToGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var group: CategoryGroup
    let allCategories: [Category]
    
    @State private var selectedCategories: Set<UUID> = []
    
    private var availableCategories: [Category] {
        allCategories.filter { category in
            !group.contains(category)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if availableCategories.isEmpty {
                    ContentUnavailableView(
                        "All Categories Added",
                        systemImage: "checkmark.circle",
                        description: Text("All expense categories are already in this group.")
                    )
                } else {
                    ForEach(availableCategories) { category in
                        Button {
                            toggleCategory(category)
                        } label: {
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundStyle(Color(hex: category.colorHex) ?? .gray)
                                    .frame(width: 30)
                                
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                if selectedCategories.contains(category.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedCategories.count))") {
                        addSelectedCategories()
                        dismiss()
                    }
                    .disabled(selectedCategories.isEmpty)
                }
            }
        }
    }
    
    private func toggleCategory(_ category: Category) {
        if selectedCategories.contains(category.id) {
            selectedCategories.remove(category.id)
        } else {
            selectedCategories.insert(category.id)
        }
    }
    
    private func addSelectedCategories() {
        for categoryId in selectedCategories {
            if let category = allCategories.first(where: { $0.id == categoryId }) {
                group.addCategory(category)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CategoryGroupListView()
    }
    .modelContainer(for: [CategoryGroup.self, Category.self, Budget.self], inMemory: true)
}
