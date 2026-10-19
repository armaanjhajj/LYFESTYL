//
//  DashboardView.swift
//  LYFESTYL
//
//  Top right of the camera, laid out like the Health app's Summary: a Today
//  card with rings, today's meals, a card per nutrient with its last seven
//  days (each opens a full chart), highlights from your habits, and the
//  history by day.
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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TodayCard(
                        title: "Today",
                        date: .now,
                        nutrition: todayMeals.map(\.nutrition).total,
                        goals: goals
                    )

                    SectionTitle("Meals")
                    MealsCard(meals: todayMeals, empty: "Nothing yet today.", editing: $editing)

                    SectionTitle("Nutrients")
                    ForEach(Macro.allCases) { macro in
                        NavigationLink(value: macro) {
                            MetricCard(macro: macro, days: days, lastMeal: todayMeals.first?.loggedAt)
                        }
                        .buttonStyle(.plain)
                    }

                    SectionTitle("Highlights")
                    HighlightCards(result: HabitEngine.evaluate(days: days, goals: goals))

                    if !past.isEmpty {
                        SectionTitle("History")
                        HistoryCard(days: past, goal: goals.calories)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(.appBackground)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TodayCard(
                    title: Formatting.relativeDay(day),
                    date: day,
                    nutrition: meals.map(\.nutrition).total,
                    goals: goalStore.goals
                )
                SectionTitle("Meals")
                MealsCard(meals: meals, empty: "No meals on this day.", editing: $editing)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(.appBackground)
        .capsNavigationTitle(Formatting.relativeDay(day))
        .mealEditor(item: $editing)
    }
}

// MARK: - Cards

/// The rounded card every block of the dashboard sits on.
struct DashboardCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// A big black-caps heading between groups of cards.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .blackCaps(.title3, tracking: 0.6)
            .padding(.top, 14)
            .padding(.leading, 4)
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
        DashboardCard {
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

private struct MealsCard: View {
    let meals: [MealEntry]
    let empty: String
    @Binding var editing: MealDraft?

    var body: some View {
        DashboardCard {
            if meals.isEmpty {
                Text(empty)
                    .font(.body)
                    .foregroundStyle(.appTextMuted)
            } else {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    if index > 0 { Divider().padding(.vertical, 10) }
                    Button { editing = MealDraft(editing: meal) } label: { MealRow(meal: meal) }
                        .buttonStyle(.plain)
                }
            }
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
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Formatting.calories(n.calories)) cal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                MacroLine(protein: n.protein, carbs: n.carbs, fat: n.fat)
            }
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
        DashboardCard {
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

private struct HighlightCards: View {
    let result: HabitEngine.Result

    var body: some View {
        switch result {
        case .notEnoughData(let logged):
            DashboardCard {
                CardHeader(symbol: "chart.bar.fill", title: "Habits", tint: .appAccentSecondary)
                Text("Log \(HabitEngine.minimumDays) days to see your habits. \(logged) so far.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                    .padding(.top, 10)
            }
        case .habits(let habits):
            ForEach(habits) { habit in
                HighlightCard(habit: habit)
            }
        }
    }
}

/// A habit the way Health shows a highlight: a sentence, then the average
/// against the goal as two bars.
struct HighlightCard: View {
    let habit: Habit

    var body: some View {
        let tint = habit.macro.accent
        let top = max(habit.average, habit.goal, 1)
        DashboardCard {
            CardHeader(symbol: habit.macro.symbol, title: habit.macro.name, tint: tint)
            Text([habit.title + ".", habit.detail].filter { $0 != "." && !$0.isEmpty }.joined(separator: " "))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.appTextEmphasis)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Divider().padding(.vertical, 14)
            VStack(alignment: .leading, spacing: 12) {
                comparison("Average", habit.average, fraction: habit.average / top, color: tint)
                comparison("Goal", habit.goal, fraction: habit.goal / top, color: .appTextMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func comparison(_ label: String, _ value: Double, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(habit.macro == .calories ? Formatting.calories(value) : Formatting.grams(value, includeUnit: false))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(color)
                Text(habit.macro.unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .font(.caption.weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(.appTextMuted)
                    .padding(.leading, 4)
            }
            .monospacedDigit()
            GeometryReader { geo in
                Capsule()
                    .fill(color)
                    .frame(width: max(8, geo.size.width * min(fraction, 1)), height: 10)
            }
            .frame(height: 10)
        }
    }
}

private struct HistoryCard: View {
    let days: [DayTotal]
    let goal: Double

    var body: some View {
        DashboardCard {
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                if index > 0 { Divider().padding(.vertical, 10) }
                NavigationLink(value: day.day) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Formatting.relativeDay(day.day))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.appTextEmphasis)
                            Text(day.mealCount == 1 ? "1 meal" : "\(day.mealCount) meals")
                                .font(.subheadline)
                                .foregroundStyle(.appTextMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Formatting.calories(day.nutrition.calories)) cal")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(day.nutrition.calories > goal * 1.1 ? .appDestructive : .appTextEmphasis)
                            MacroLine(protein: day.nutrition.protein, carbs: day.nutrition.carbs, fat: day.nutrition.fat)
                        }
                        .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.appTextMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
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
