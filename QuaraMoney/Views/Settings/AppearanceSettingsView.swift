import SwiftUI

/// Everything that changes how the app looks, on one screen: the light/dark
/// theme, the income/expense accent pair, and the iPad layout switch.
///
/// The screen leads with a live sample so the chosen pair can be judged in the
/// places the colors actually show up — chart bars and amounts — against the
/// theme they will be seen on. Picking a theme flips the whole app (the root
/// applies `preferredColorScheme`), so the sample re-renders with it.
///
/// Absorbs the former `ThemeSettingsView`, which existed only to hold the two
/// color pickers.
struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var selectedTheme: QuaraMoneyApp.AppTheme = .system
    @AppStorage("useSidebarOniPad") private var useSidebarOniPad: Bool = true
    @Bindable private var themeManager = ThemeManager.shared

    private static let defaultIncomeHex = "#34C759" // Green
    private static let defaultExpenseHex = "#FF3B30" // Red

    private var isUsingDefaultColors: Bool {
        themeManager.incomeColorHex == Self.defaultIncomeHex
            && themeManager.expenseColorHex == Self.defaultExpenseHex
    }

    var body: some View {
        Form {
            Section {
                AppearanceSamplePreview(
                    income: themeManager.incomeColor,
                    expense: themeManager.expenseColor
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("settings.appTheme".localized, selection: $selectedTheme) {
                    ForEach(QuaraMoneyApp.AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("settings.appTheme".localized)
            }

            Section("settings.incomeColor".localized) {
                swatchGrid(selection: $themeManager.incomeColorHex)
            }

            Section("settings.expenseColor".localized) {
                swatchGrid(selection: $themeManager.expenseColorHex)
            }

            if UIDevice.current.userInterfaceIdiom == .pad {
                Section {
                    Toggle(isOn: $useSidebarOniPad) {
                        Label {
                            Text(L10n.Settings.useSidebarOniPad)
                        } icon: {
                            ListIconView(systemImage: "sidebar.left", color: Color(.systemGray))
                        }
                    }
                }
            }
        }
        // Tighter than the default grouped spacing: the screen is only worth
        // building around a live sample if the sample and the controls that
        // drive it are visible at the same time.
        .listSectionSpacing(14)
        .contentMargins(.top, 10, for: .scrollContent)
        .navigationTitle("settings.appearance".localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("analysis.pro.filter.reset".localized) {
                    withAnimation {
                        themeManager.incomeColorHex = Self.defaultIncomeHex
                        themeManager.expenseColorHex = Self.defaultExpenseHex
                    }
                }
                .disabled(isUsingDefaultColors)
            }
        }
    }

    /// The whole 18-colour palette as 9 × 2 — the grid is sized so that the
    /// sample, the theme switch and both pickers fit on one screen without
    /// scrolling, which is the point of showing a live sample at all.
    private func swatchGrid(selection: Binding<String>) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 9),
            spacing: 4
        ) {
            ForEach(AppTheme.colors, id: \.self) { colorHex in
                swatch(colorHex, selection: selection)
            }
        }
    }

    private func swatch(_ colorHex: String, selection: Binding<String>) -> some View {
        let isSelected = selection.wrappedValue == colorHex
        return Circle()
            .fill(Color(hex: colorHex) ?? .gray)
            .frame(width: 26, height: 26)
            .overlay {
                // Ring outside the swatch rather than a checkmark inside it:
                // legible at this size, where a glyph would not be.
                Circle()
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.85 : 0), lineWidth: 2)
                    .padding(-3)
            }
            // The tap target is the whole grid cell, not the 26pt circle.
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selection.wrappedValue = colorHex
                }
            }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Illustrative sample of the accent pair in the two places it actually shows
/// up — chart bars and amounts — drawn with plain shapes and fixed proportions
/// rather than real data, so it reads as a swatch and never as a report.
private struct AppearanceSamplePreview: View {
    let income: Color
    let expense: Color

    /// Deliberately meaningless: this is a drawing, not a chart.
    /// Kept in the 0.45...1 band: below that a bar is shorter than it is wide
    /// and reads as a dot instead.
    private let incomeBars: [CGFloat] = [0.62, 0.48, 0.88, 0.55, 0.74, 0.45, 0.68, 1.00,
                                         0.52, 0.72, 0.58, 0.82, 0.50, 0.78, 0.60, 0.92]
    private let expenseBars: [CGFloat] = [0.54, 0.72, 0.46, 0.80, 0.50, 0.64, 0.58, 0.47,
                                          0.76, 0.55, 0.68, 0.49, 0.84, 0.52, 0.74, 0.57]

    /// Tallest a bar gets in each direction from the centre line. Bars stay
    /// `barWidth` wide and reach several times that, so they read as bars
    /// rather than as the horizontal pills a full-cell-width capsule draws.
    private let barReach: CGFloat = 38
    private let barWidth: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Text("common.preview".localized)
                    .appFont(.caption2, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer(minLength: 0)

                legendItem(income, title: "transaction.type.income".localized)
                legendItem(expense, title: "transaction.type.expense".localized)
            }

            chart

            // No divider under the chart: its own baseline gridline and axis
            // row already close it off, and a third horizontal line here read
            // as clutter.
            VStack(spacing: 9) {
                mockRow(color: income, nameWidth: 92, amountWidth: 52)
                mockRow(color: expense, nameWidth: 68, amountWidth: 40)
            }
            .padding(.top, 3)
        }
        // 16pt all round: the platform's standard list-cell content inset, so
        // the card's contents line up with the row content of every other card
        // on the screen rather than sitting 4pt tighter.
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: CornerRadius.card, style: .continuous)
        )
    }

    /// Mirrored bars over a zero line, framed by gridlines and stand-in axis
    /// labels — the shape of the Analysis cash-flow chart at a size where it
    /// still reads as one. Nothing here is derived from data.
    private var chart: some View {
        VStack(spacing: 7) {
            ZStack {
                VStack(spacing: 0) {
                    gridline(isZeroLine: false)
                    Spacer(minLength: 0)
                    gridline(isZeroLine: true)
                    Spacer(minLength: 0)
                    gridline(isZeroLine: false)
                }

                HStack(alignment: .center, spacing: 4) {
                    ForEach(incomeBars.indices, id: \.self) { index in
                        VStack(spacing: 2) {
                            Capsule()
                                .fill(income)
                                .frame(width: barWidth, height: max(barWidth, barReach * incomeBars[index]))
                                .frame(maxHeight: .infinity, alignment: .bottom)

                            Capsule()
                                .fill(expense)
                                .frame(width: barWidth, height: max(barWidth, barReach * expenseBars[index]))
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: barReach * 2 + 2)

            axisLabels
        }
        .accessibilityHidden(true)
    }

    private func gridline(isZeroLine: Bool) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(isZeroLine ? 0.16 : 0.07))
            .frame(height: 1)
    }

    /// Neutral placeholders where the real chart prints its date axis.
    private var axisLabels: some View {
        HStack(spacing: 0) {
            ForEach(0..<4) { _ in
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 16, height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func legendItem(_ color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// A transaction row reduced to its shapes: tinted category dot, a neutral
    /// placeholder for the name, and the amount in the accent color.
    private func mockRow(color: Color, nameWidth: CGFloat, amountWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 22, height: 22)
                .overlay {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }

            Capsule()
                .fill(Color.primary.opacity(0.14))
                .frame(width: nameWidth, height: 7)

            Spacer(minLength: 8)

            Capsule()
                .fill(color)
                .frame(width: amountWidth, height: 7)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
