//
//  DashboardView.swift
//  LYFESTYL
//
//  Top right of the camera. Today against your goals, today's meals, habits
//  worth a look, the last seven days, and the full history by day.
//

import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(GoalStore.self) private var goalStore

    @Query private var meals: [MealEntry]
    @State private var editing: MealDraft?
    @State private var chartMacro: Macro = .calories

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
        let today = todayMeals.map(\.nutrition).total

        NavigationStack {
            List {
                Section {
                    DaySummary(nutrition: today, goals: goals)
                } header: {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day())).sectionHeader()
                }

                Section {
                    if todayMeals.isEmpty {
                        Text("Nothing logged yet today. Snap a meal to start.")
                            .foregroundStyle(.appTextMuted)
                    } else {
                        MealRows(meals: todayMeals, editing: $editing)
                    }
                } header: {
                    Text("MEALS").sectionHeader()
                }

                Section {
                    HabitRows(result: HabitEngine.evaluate(days: days, goals: goals))
                } header: {
                    Text("HABITS").sectionHeader()
                } footer: {
                    Text("Based on the last \(HabitEngine.windowDays) finished days you logged.")
                }

                Section {
                    WeekChart(days: days, macro: chartMacro, goal: goals[chartMacro])
                    Picker("Show", selection: $chartMacro) {
                        ForEach(Macro.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                } header: {
                    Text("LAST 7 DAYS").sectionHeader()
                }

                let past = days.filter { !Calendar.current.isDateInToday($0.day) }
                if !past.isEmpty {
                    Section {
                        ForEach(past) { day in
                            NavigationLink(value: day.day) { DayRow(day: day, goal: goals.calories) }
                        }
                    } header: {
                        Text("HISTORY").sectionHeader()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.appBackground)
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
                DaySummary(nutrition: meals.map(\.nutrition).total, goals: goalStore.goals)
            }
            Section {
                if meals.isEmpty {
                    Text("No meals on this day.").foregroundStyle(.appTextMuted)
                } else {
                    MealRows(meals: meals, editing: $editing)
                }
            } header: {
                Text("MEALS").sectionHeader()
            }
        }
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .capsNavigationTitle(Formatting.relativeDay(day))
        .mealEditor(item: $editing)
    }
}

// MARK: - Pieces

/// The calorie ring beside three macro bars.
struct DaySummary: View {
    let nutrition: Nutrition
    let goals: Goals

    var body: some View {
        HStack(spacing: 20) {
            CalorieRing(eaten: nutrition.calories, goal: goals.calories)
                .frame(width: 128, height: 128)
            VStack(spacing: 14) {
                ForEach([Macro.protein, .carbs, .fat]) { macro in
                    MacroBar(macro: macro, value: nutrition[macro], goal: goals[macro])
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct CalorieRing: View {
    let eaten: Double
    let goal: Double

    private var left: Double { goal - eaten }

    var body: some View {
        ZStack {
            Chart {
                if eaten > goal {
                    SectorMark(angle: .value("Eaten", eaten), innerRadius: .ratio(0.8))
                        .foregroundStyle(Color.appDestructive)
                } else {
                    SectorMark(angle: .value("Eaten", max(eaten, 0.0001)), innerRadius: .ratio(0.8), angularInset: eaten > 0 ? 1.5 : 0)
                        .cornerRadius(4)
                        .foregroundStyle(Macro.calories.accent)
                    SectorMark(angle: .value("Left", max(left, 0.0001)), innerRadius: .ratio(0.8), angularInset: eaten > 0 ? 1.5 : 0)
                        .cornerRadius(4)
                        .foregroundStyle(Color.appSurface)
                }
            }
            .chartLegend(.hidden)

            VStack(spacing: 0) {
                Text(Formatting.calories(abs(left)))
                    .font(.title2.weight(.black))
                    .foregroundStyle(.appTextEmphasis)
                    .contentTransition(.numericText())
                Text(left >= 0 ? "KCAL LEFT" : "KCAL OVER")
                    .font(.caption2.weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(left >= 0 ? .appTextMuted : .appDestructive)
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Formatting.calories(eaten)) of \(Formatting.calories(goal)) calories")
        .accessibilityValue(left >= 0 ? "\(Formatting.calories(left)) left" : "\(Formatting.calories(-left)) over")
    }
}

private struct MacroBar: View {
    let macro: Macro
    let value: Double
    let goal: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(macro.label)
                    .font(.caption.weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(.appTextEmphasis)
                Spacer()
                Text("\(Formatting.grams(value, includeUnit: false)) / \(Formatting.grams(goal))")
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
                    .monospacedDigit()
            }
            ProgressView(value: goal > 0 ? min(value / goal, 1) : 0)
                .tint(macro.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.name), \(Formatting.grams(value)) of \(Formatting.grams(goal))")
    }
}

/// Meals as rows: tap to edit in the drawer, swipe to delete.
private struct MealRows: View {
    let meals: [MealEntry]
    @Binding var editing: MealDraft?

    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health

    var body: some View {
        ForEach(meals) { meal in
            Button { editing = MealDraft(editing: meal) } label: { MealRow(meal: meal) }
        }
        .onDelete { offsets in
            MealLog(context: context, health: health).delete(offsets.map { meals[$0] })
        }
    }
}

private struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        let n = meal.nutrition
        HStack(spacing: 12) {
            IconChip(symbol: meal.meal.symbol, tint: .appAccent, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                    .lineLimit(1)
                Text("\(meal.meal.rawValue) · \(Formatting.timeOfDay(meal.loggedAt))")
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Formatting.calories(n.calories)) kcal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appTextEmphasis)
                Text(Formatting.macroLine(protein: n.protein, carbs: n.carbs, fat: n.fat))
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DayRow: View {
    let day: DayTotal
    let goal: Double

    var body: some View {
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
                Text("\(Formatting.calories(day.nutrition.calories)) kcal")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(day.nutrition.calories > goal * 1.1 ? .appDestructive : .appTextEmphasis)
                Text(Formatting.macroLine(protein: day.nutrition.protein, carbs: day.nutrition.carbs, fat: day.nutrition.fat))
                    .font(.caption)
                    .foregroundStyle(.appTextMuted)
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HabitRows: View {
    let result: HabitEngine.Result

    var body: some View {
        switch result {
        case .notEnoughData(let logged):
            HStack(alignment: .top, spacing: 12) {
                IconChip(symbol: "chart.bar.fill", tint: .appAccentSecondary, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Keep logging")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.appTextEmphasis)
                    Text("Habits show up after \(HabitEngine.minimumDays) logged days. You have \(logged) in the last week.")
                        .font(.subheadline)
                        .foregroundStyle(.appTextMuted)
                }
            }
        case .habits(let habits):
            ForEach(habits) { habit in
                HStack(alignment: .top, spacing: 12) {
                    IconChip(symbol: habit.symbol, tint: habit.isPositive ? .appAccent : .appWarning, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(habit.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.appTextEmphasis)
                        Text(habit.detail)
                            .font(.subheadline)
                            .foregroundStyle(.appTextMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// One bar per day for the chosen macro, with the goal as a dashed rule.
private struct WeekChart: View {
    let days: [DayTotal]
    let macro: Macro
    let goal: Double

    private var week: [DayTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let byDay = Dictionary(uniqueKeysWithValues: days.map { ($0.day, $0) })
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byDay[day] ?? DayTotal(day: day, nutrition: .zero, mealCount: 0)
        }
    }

    var body: some View {
        let week = week
        let logged = week.filter { $0.mealCount > 0 }
        let average = logged.isEmpty ? 0 : logged.map { $0.nutrition[macro] }.reduce(0, +) / Double(logged.count)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(logged.isEmpty ? "--" : Formatting.value(average, for: macro))
                    .font(.title3.weight(.black))
                    .foregroundStyle(.appTextEmphasis)
                    .monospacedDigit()
                Text("DAILY AVERAGE")
                    .font(.caption2.weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(.appTextMuted)
            }
            Chart {
                ForEach(week) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value(macro.name, day.nutrition[macro])
                    )
                    .foregroundStyle(macro.accent)
                    .cornerRadius(4)
                }
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Color.appTextMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Goal")
                            .font(.caption2)
                            .foregroundStyle(.appTextMuted)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Formatting.shortWeekday(date))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Color.appTextMuted.opacity(0.2))
                    AxisValueLabel()
                }
            }
            .frame(height: 170)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(macro.name), last 7 days")
        .accessibilityValue(logged.isEmpty ? "No meals logged" : "Daily average \(Formatting.value(average, for: macro))")
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
