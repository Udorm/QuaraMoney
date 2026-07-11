import SwiftUI
import SwiftData

struct AddCategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedType: TransactionType = .expense
    @State private var selectedIcon: String = "list.bullet"
    @State private var selectedColorHex: String = "#FF3B30"
    @State private var showingIconPicker = false

    private var categoryToEdit: Category?

    private var categoryColor: Color {
        Color(hex: selectedColorHex) ?? .blue
    }

    /// Whether the category being edited is a system category (read-only)
    private var isSystemCategory: Bool {
        categoryToEdit?.isSystem == true
    }

    /// When creating a new category, seeds the type picker so the category
    /// matches the transaction being entered (e.g. an Expense entry pre-selects
    /// the Expense type). Ignored for `.transfer`, which has no categories.
    init(categoryToEdit: Category? = nil, initialType: TransactionType? = nil) {
        self.categoryToEdit = categoryToEdit

        if let category = categoryToEdit {
            _name = State(initialValue: category.name)
            _selectedType = State(initialValue: category.type)
            _selectedIcon = State(initialValue: category.icon)
            _selectedColorHex = State(initialValue: category.colorHex)
        } else if let initialType, initialType == .income || initialType == .expense {
            _selectedType = State(initialValue: initialType)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    categoryPreview
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }

                Section("category.details".localized) {
                    TextField("category.name".localized, text: $name)
                        .disabled(isSystemCategory)

                    // Dropdown menu style type picker.
                    Picker("common.type".localized, selection: $selectedType) {
                        Text("category.expense".localized).tag(TransactionType.expense)
                        Text("category.income".localized).tag(TransactionType.income)
                    }
                    .pickerStyle(.menu)
                    .disabled(isSystemCategory)
                }

                Section("category.appearance".localized) {
                    colorSwatches

                    Button {
                        showingIconPicker = true
                    } label: {
                        HStack {
                            Text("category.icon".localized)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selectedIcon)
                                .foregroundStyle(categoryColor)
                            Image(systemName: "chevron.right")
                                .font(.app(.footnote, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSystemCategory)
                }
                .disabled(isSystemCategory)
            }
            .navigationTitle(categoryToEdit != nil ? "category.editCategory".localized : "category.newCategory".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                if !isSystemCategory {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            saveCategory()
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                NavigationStack {
                    IconPickerView(selectedIcon: $selectedIcon, selectedColorHex: $selectedColorHex)
                        .navigationTitle(L10n.Category.selectIcon)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L10n.Common.done) {
                                    showingIconPicker = false
                                }
                            }
                        }
                }
            }
        }
    }

    // MARK: - Category preview
    //
    // Deliberately unlike the wallet card preview (a full-width gradient "card"):
    // this is a centered circular *badge* inside concentric rings, with the name
    // as a tag chip — the visual language categories use throughout the app.

    private var categoryPreview: some View {
        VStack(spacing: 16) {
            ZStack {
                // Concentric halo rings — the category "token" motif.
                ForEach(0..<3) { ring in
                    Circle()
                        .stroke(categoryColor.opacity(0.20 - Double(ring) * 0.055), lineWidth: 1.5)
                        .frame(width: 96 + CGFloat(ring) * 28, height: 96 + CGFloat(ring) * 28)
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [categoryColor, categoryColor.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: categoryColor.opacity(0.35), radius: 10, x: 0, y: 6)

                Image(systemName: selectedIcon)
                    .appFont(size: 38)
                    .foregroundStyle(.white)
            }
            .frame(height: 152)

            // Name + type as a tag chip.
            HStack(spacing: 6) {
                Image(systemName: selectedType == .income ? "arrow.down.left" : "arrow.up.right")
                    .font(.app(.caption2, weight: .bold))
                Text(name.isEmpty ? "category.name".localized : name)
                    .font(.app(.subheadline, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(categoryColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(categoryColor.opacity(0.14), in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .animation(.snappy, value: selectedColorHex)
        .animation(.snappy, value: selectedIcon)
        .animation(.snappy, value: selectedType)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.Common.preview): \(name.isEmpty ? "category.name".localized : name)")
    }

    // MARK: - Inline color swatches (matches AddWalletView)

    private var colorSwatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AppTheme.colors, id: \.self) { colorHex in
                    let isSelected = colorHex.caseInsensitiveCompare(selectedColorHex) == .orderedSame
                    Button {
                        selectedColorHex = colorHex
                        HapticManager.shared.selection()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: colorHex) ?? .gray)
                                .frame(width: 32, height: 32)
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.app(.caption, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? (Color(hex: colorHex) ?? .gray).opacity(0.35) : .clear, lineWidth: 3)
                                .frame(width: 40, height: 40)
                        )
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(colorHex)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func saveCategory() {
        guard !isSystemCategory else { return }

        if let category = categoryToEdit {
            category.name = name
            category.icon = selectedIcon
            category.colorHex = selectedColorHex
            category.type = selectedType
        } else {
            let category = Category(name: name, icon: selectedIcon, colorHex: selectedColorHex, type: selectedType)
            modelContext.insert(category)
        }
    }
}
