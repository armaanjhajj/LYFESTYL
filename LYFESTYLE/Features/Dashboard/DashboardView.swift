//
//  DashboardView.swift
//  LYFESTYL
//
//  Top right of the camera, laid out like the Health app's Summary: a Today
//  card with rings, today's food (swipe to delete), a card per nutrient with
//  its last seven days (each opens a full chart), and the history by day.
//

import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GoalStore.self) private var goalStore

    @Query private var meals: [MealEntry]
    @State private var editing: MealDraft?

    init() {
        // A year is plenty for a dashboard; older meals still sync and export.
        let since = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .distantPast
        _meals = Query(
            filter: #Predicate<MealEntry> { $0.loggedAt >= since },
            sort: \MealEntry.loggedAt,
            order: .reverse
        )
    }

    var body: some View {
        let goals = goalStore.goals
        let days = HabitEngine.dailyTotals(meals.map { ($0.loggedAt, $0.nutrition) })
        let todayMeals = meals.filter { Calendar.current.isDateInToday($0.loggedAt) }
        let past = days.filter { !Calendar.current.isDateInToday($0.day) }

        NavigationStack {
            List {
                Section {
                    TodayCard(
                        title: "Today",
                        date: .now,
                        nutrition: todayMeals.map(\.nutrition).total,
                        goals: goals
                    )
                }

                FoodSection(meals: todayMeals, empty: "Nothing yet today.", editing: $editing)

                ForEach(Macro.allCases) { macro in
                    Section {
                        MetricCard(macro: macro, days: days, lastMeal: todayMeals.first?.loggedAt)
                            .background { NavigationLink(value: macro) { EmptyView() }.opacity(0) }
                    } header: {
                        if macro == .calories { SectionTitle("Nutrients") }
                    }
                }

                if !past.isEmpty {
                    Section {
                        ForEach(past) { day in
                            HistoryRow(day: day, goal: goals.calories)
                                .background { NavigationLink(value: day.day) { EmptyView() }.opacity(0) }
                        }
                    } header: {
                        SectionTitle("History")
                    }
                }
            }
            .dashboardListStyle()
            .navigationDestination(for: Macro.self) { MetricDetailView(macro: $0, days: days) }
            .navigationDestination(for: Date.self) { DayDetailView(day: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { NavHeaderTitle("Dashboard") }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .mealEditor(item: $editing)
        }
        .presentationBackground(.appBackground)
    }
}

// MARK: - Day detail

struct DayDetailView: View {
    let day: Date

    @Environment(GoalStore.self) private var goalStore
    @Query private var meals: [MealEntry]
    @State private var editing: MealDraft?

    init(day: Date) {
        self.day = day
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _meals = Query(
            filter: #Predicate<MealEntry> { $0.loggedAt >= start && $0.loggedAt < end },
            sort: \MealEntry.loggedAt
        )
    }

    var body: some View {
        List {
            Section {
                TodayCard(
                    title: Formatting.relativeDay(day),
                    date: day,
                    nutrition: meals.map(\.nutrition).total,
                    goals: goalStore.goals
                )
            }
            FoodSection(meals: meals, empty: "Nothing on this day.", editing: $editing)
        }
        .dashboardListStyle()
        .capsNavigationTitle(Formatting.relativeDay(day))
        .mealEditor(item: $editing)
    }
}

// MARK: - Cards

extension View {
    /// The dashboard's list: every section a rounded card on the palette's
    /// surface tone, spaced like the Health app's Summary.
    func dashboardListStyle() -> some View {
        self
            .listStyle(.insetGrouped)
            .listSectionSpacing(12)
            .scrollContentBackground(.hidden)
            .background(.appBackground)
            .contentMargins(.top, 4, for: .scrollContent)
    }
}

/// Cards sit on the surface tone.
private extension View {
    func cardRow() -> some View {
        listRowBackground(Color.appSurface)
            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
    }
}

/// A big black-caps heading between groups of cards.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .blackCaps(.title3, tracking: 0.6)
            .textCase(nil)
            .padding(.top, 8)
            .padding(.leading, -12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A card's top row: colored icon and title on the left, a detail and an
/// optional chevron on the right.
struct CardHeader: View {
    let symbol: String
    let title: String
    let tint: Color
    var detail: String? = nil
    var chevron = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.appTextMuted)
            }
        }
        .font(.headline)
        .foregroundStyle(tint)
    }
}

/// Like the Activity card: calories over the three macros in colored
/// columns, with concentric rings for each against its goal.
private struct TodayCard: View {
    let title: String
    let date: Date
    let nutrition: Nutrition
    let goals: Goals

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(
                symbol: "fork.knife",
                title: title,
                tint: Macro.calories.accent,
                detail: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            )
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Formatting.calories(nutrition.calories))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.appTextEmphasis)
                            .contentTransition(.numericText(value: nutrition.calories))
                        Text("/ \(Formatting.calories(goals.calories)) cal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.appTextMuted)
                    }
                    HStack(spacing: 0) {
                        ForEach([Macro.protein, .carbs, .fat]) { macro in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(macro.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(macro.accent)
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(Formatting.grams(nutrition[macro], includeUnit: false))
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.appTextEmphasis)
                                    Text("g")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.appTextMuted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if macro != .fat {
                                Divider().frame(height: 34).padding(.horizontal, 6)
                            }
                        }
                    }
                }
                .monospacedDigit()
                ConcentricRings(nutrition: nutrition, goals: goals)
                    .frame(width: 96, height: 96)
            }
            .padding(.top, 12)
        }
        .cardRow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(Formatting.calories(nutrition.calories)) of \(Formatting.calories(goals.calories)) calories, \(Formatting.grams(nutrition.protein)) protein, \(Formatting.grams(nutrition.carbs)) carbs, \(Formatting.grams(nutrition.fat)) fat")
    }
}

/// Four nested rings, calories outside, like the Activity rings.
private struct ConcentricRings: View {
    let nutrition: Nutrition
    let goals: Goals

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = side * 0.09
            ZStack {
                ForEach(Array(Macro.allCases.enumerated()), id: \.element) { index, macro in
                    ProgressRing(
                        fraction: goals[macro] > 0 ? nutrition[macro] / goals[macro] : 0,
                        tint: macro.accent,
                        lineWidth: line
                    )
                    .padding(CGFloat(index) * (line + 2))
                }
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}

/// Today's (or a day's) food: tap to open in the drawer, swipe to delete.
private struct FoodSection: View {
    let meals: [MealEntry]
    let empty: String
    @Binding var editing: MealDraft?

    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health

    var body: some View {
        Section {
            if meals.isEmpty {
                Text(empty)
                    .foregroundStyle(.appTextMuted)
                    .cardRow()
            } else {
                ForEach(meals) { meal in
                    Button { editing = MealDraft(editing: meal) } label: { MealRow(meal: meal) }
                        .buttonStyle(.plain)
                        .cardRow()
                }
                .onDelete { offsets in
                    MealLog(context: context, health: health).delete(offsets.map { meals[$0] })
                }
            }
        } header: {
            SectionTitle("Food")
        }
    }
}

private struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        let n = meal.nutrition
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                    .lineLimit(1)
                Text(Formatting.timeOfDay(meal.loggedAt))
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer(minLength: 8)
            Text("\(Formatting.calories(n.calories)) cal")
                .font(.body.weight(.semibold))
                .foregroundStyle(.appTextEmphasis)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// One nutrient: today's amount, big, and the last seven days as small bars,
/// today's in color. Opens the full chart.
private struct MetricCard: View {
    let macro: Macro
    let days: [DayTotal]
    let lastMeal: Date?

    var body: some View {
        let week = WeekValues(days: days, macro: macro)
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(
                symbol: macro.symbol,
                title: macro.name,
                tint: macro.accent,
                detail: lastMeal.map(Formatting.timeOfDay),
                chevron: true
            )
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(macro == .calories ? Formatting.calories(week.today) : Formatting.grams(week.today, includeUnit: false))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.appTextEmphasis)
                        .monospacedDigit()
                    Text(macro.unit)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.appTextMuted)
                }
                Spacer()
                Chart(Array(week.values.enumerated()), id: \.offset) { index, value in
                    BarMark(x: .value("Day", index), y: .value(macro.name, value), width: 7)
                        .cornerRadius(2)
                        .foregroundStyle(index == week.values.count - 1 ? macro.accent : Color.appTextMuted.opacity(0.35))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 90, height: 44)
            }
            .padding(.top, 14)
        }
        .cardRow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.name) today, \(Formatting.value(week.today, for: macro))")
        .accessibilityHint("Shows the full chart")
    }
}

/// The last seven days of one macro, oldest first, today last.
private struct WeekValues {
    let values: [Double]
    var today: Double { values.last ?? 0 }

    init(days: [DayTotal], macro: Macro) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0.nutrition[macro]) })
        values = (0..<7).reversed().map { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).flatMap { byDay[$0] } ?? 0
        }
    }
}

private struct HistoryRow: View {
    let day: DayTotal
    let goal: Double

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatting.relativeDay(day.day))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                Text("\(day.mealCount) logged")
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer()
            Text("\(Formatting.calories(day.nutrition.calories)) cal")
                .font(.body.weight(.semibold))
                .foregroundStyle(day.nutrition.calories > goal * 1.1 ? .appDestructive : .appTextEmphasis)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.appTextMuted)
        }
        .contentShape(Rectangle())
        .cardRow()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editing logged meals

private struct MealEditor: ViewModifier {
    @Binding var item: MealDraft?

    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health

    func body(content: Content) -> some View {
        content.sheet(item: $item) { draft in
            ReviewDrawer(
                draft: draft,
                onLog: {
                    if let entry = draft.editing {
                        MealLog(context: context, health: health).update(entry, items: draft.foods, at: draft.loggedAt)
                    }
                    item = nil
                },
                onDelete: {
                    if let entry = draft.editing {
                        MealLog(context: context, health: health).delete([entry])
                    }
                    item = nil
                },
                onDismiss: { item = nil }
            )
        }
    }
}

extension View {
    /// Present a logged meal in the review drawer, saving or deleting on close.
    func mealEditor(item: Binding<MealDraft?>) -> some View {
        modifier(MealEditor(item: item))
    }
}
