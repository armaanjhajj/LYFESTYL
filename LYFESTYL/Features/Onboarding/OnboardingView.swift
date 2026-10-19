//
//  OnboardingView.swift
//  LYFESTYL
//
//  First launch only. The app icon, a short welcome, then setup one step at a
//  time: profile, Apple Health, body, goal, activity, and the daily targets
//  that come out of them. Everything can be changed later in Account.
//

import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    @Environment(GoalStore.self) private var goalStore
    @Environment(HealthService.self) private var health
    @State private var path: [Step] = []
    @State private var bodyProfile = BodyProfile()

    enum Step: Hashable { case welcome, profile, health, body, aim, activity, plan }

    var body: some View {
        NavigationStack(path: $path) {
            StartPage { path.append(.welcome) }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Step.self, destination: page)
        }
        .tint(.appAccent)
        .onAppear { if let saved = goalStore.profile { bodyProfile = saved } }
    }

    @ViewBuilder
    private func page(_ step: Step) -> some View {
        switch step {
        case .welcome:
            WelcomePage { advance(from: step) }
        case .profile:
            ProfilePage { advance(from: step) }
        case .health:
            HealthPage(profile: $bodyProfile) { advance(from: step) }
        case .body:
            OnboardingPage(symbol: "figure.stand", tint: Solar.blue, title: "About You") {
                BodySection(profile: $bodyProfile, showsHealthFill: false)
            } actions: {
                PrimaryButton("Continue") { advance(from: step) }
            }
        case .aim:
            OnboardingPage(symbol: "target", tint: Macro.calories.accent, title: "Your Goal") {
                Section {
                    Picker("Goal", selection: $bodyProfile.aim) {
                        ForEach(BodyProfile.Aim.allCases, id: \.self) { aim in
                            Label {
                                Text(aim.label)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.appTextEmphasis)
                            } icon: {
                                Image(systemName: aim.symbol)
                                    .foregroundStyle(.appAccent)
                            }
                            .padding(.vertical, 6)
                            .tag(aim)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } actions: {
                PrimaryButton("Continue") { advance(from: step) }
            }
        case .activity:
            OnboardingPage(symbol: "figure.run", tint: Macro.carbs.accent, title: "Activity") {
                Section {
                    Picker("Activity", selection: $bodyProfile.activity) {
                        ForEach(BodyProfile.Activity.allCases, id: \.self) { level in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.label)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.appTextEmphasis)
                                Text(level.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.appTextMuted)
                            }
                            .padding(.vertical, 2)
                            .tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } actions: {
                PrimaryButton("Continue") { advance(from: step) }
            }
        case .plan:
            PlanPage(goals: bodyProfile.suggestedGoals) {
                goalStore.profile = bodyProfile
                goalStore.goals = bodyProfile.suggestedGoals
                onDone()
            }
        }
    }

    private func advance(from step: Step) {
        let order: [Step] = [.welcome, .profile, .health, .body, .aim, .activity, .plan]
            .filter { $0 != .health || health.isAvailable }
        guard let index = order.firstIndex(of: step), index + 1 < order.count else { return }
        path.append(order[index + 1])
    }
}

// MARK: - Pages

/// The app icon and one button.
private struct StartPage: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(.logo)
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 140 * 0.2237, style: .continuous))
                .shadow(color: Color.appTextEmphasis.opacity(0.15), radius: 18, y: 8)
                .accessibilityLabel("LYFESTYL")
            Spacer()
            PrimaryButton("Start", action: onStart)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.appBackground)
    }
}

/// What the app does, the way Apple's apps introduce themselves.
private struct WelcomePage: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(spacing: 2) {
                    Text("Welcome to")
                    // Two-tone, like the app icon.
                    Text("\(Text("LYFE").foregroundStyle(Solar.blue))\(Text("STYL").foregroundStyle(.appAccent))")
                        .accessibilityLabel("LYFESTYL")
                }
                .screenTitle()
                .frame(maxWidth: .infinity)
                .padding(.bottom, 14)

                FeatureRow(
                    symbol: "camera.fill",
                    tint: Macro.calories.accent,
                    title: "Point and Shoot",
                    detail: "Every food in the photo comes back with calories and macros."
                )
                FeatureRow(
                    symbol: "text.viewfinder",
                    tint: Macro.protein.accent,
                    title: "Labels Read Exactly",
                    detail: "If a nutrition label is in the shot, its numbers win."
                )
                FeatureRow(
                    symbol: "slider.horizontal.3",
                    tint: Macro.carbs.accent,
                    title: "Fix Anything",
                    detail: "Slide a number, or search for something else."
                )
                FeatureRow(
                    symbol: "lock.fill",
                    tint: Macro.fat.accent,
                    title: "Stays on Your iPhone",
                    detail: "Runs on device. Photos are never saved."
                )
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(.appBackground)
        .safeAreaBar(edge: .bottom) {
            PrimaryButton("Continue", action: onContinue)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.appTextEmphasis)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.appTextMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Photo and name.
private struct ProfilePage: View {
    let onContinue: () -> Void

    @Environment(ProfileStore.self) private var profile
    @FocusState private var editingName: Bool

    var body: some View {
        @Bindable var profile = profile
        OnboardingPage(title: "Your Profile") {
            Section {
                VStack(spacing: 16) {
                    ProfilePhotoButton(size: 120)
                    TextField("Your Name", text: $profile.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.appTextEmphasis)
                        .multilineTextAlignment(.center)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($editingName)
                        .onSubmit(onContinue)
                        .padding(.vertical, 12)
                        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        } actions: {
            PrimaryButton("Continue") {
                editingName = false
                onContinue()
            }
        }
    }
}

/// Ask for Health once: it fills in the body numbers and keeps a copy of
/// what you eat.
private struct HealthPage: View {
    @Binding var profile: BodyProfile
    let onContinue: () -> Void

    @Environment(HealthService.self) private var health
    @State private var connecting = false

    var body: some View {
        OnboardingPage(
            symbol: "heart.fill",
            tint: Solar.red,
            title: "Apple Health",
            subtitle: "Fill in your height and weight, and save what you eat to Health."
        ) {
            EmptyView()
        } actions: {
            PrimaryButton("Connect", busy: connecting) {
                connecting = true
                Task {
                    health.isWritingEnabled = await health.requestAccess()
                    profile = await health.fillProfile(profile)
                    connecting = false
                    onContinue()
                }
            }
            Button("Not Now", action: onContinue)
                .font(.headline)
                .disabled(connecting)
        }
    }
}

/// The payoff: the rings fill to the targets the steps worked out.
private struct PlanPage: View {
    let goals: Goals
    let onDone: () -> Void

    @State private var filled = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Your Day")
                .screenTitle()
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 8)

            Spacer(minLength: 24)

            ZStack {
                ForEach(Array(Macro.allCases.enumerated()), id: \.element) { index, macro in
                    ProgressRing(fraction: filled ? 1 : 0, tint: macro.accent, lineWidth: 14)
                        .padding(CGFloat(index) * 20)
                        .animation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.15 * Double(index)), value: filled)
                }
            }
            .frame(width: 210, height: 210)
            .accessibilityHidden(true)

            Spacer(minLength: 24)

            VStack(spacing: 0) {
                Text(Formatting.calories(filled ? goals.calories : 0))
                    .font(.system(size: 56, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(.appTextEmphasis)
                    .contentTransition(.numericText(value: filled ? goals.calories : 0))
                    .animation(.snappy(duration: 0.8), value: filled)
                Text("CAL A DAY").sectionHeader(color: Macro.calories.accent)
            }

            HStack {
                ForEach([Macro.protein, .carbs, .fat]) { macro in
                    VStack(spacing: 2) {
                        Text(Formatting.grams(goals[macro]))
                            .font(.title3.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.appTextEmphasis)
                        Text(macro.name)
                            .font(.caption.weight(.black))
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .foregroundStyle(macro.accent)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 24)

            Spacer(minLength: 24)

            Text("A starting point, not medical advice.")
                .font(.footnote)
                .foregroundStyle(.appTextMuted)
                .padding(.bottom, 16)

            PrimaryButton("Start Logging", action: onDone)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.appBackground)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: filled)
        .accessibilityElement(children: .contain)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            filled = true
        }
    }
}

// MARK: - Shared layout

/// One setup step: a symbol and title on top, form content, and buttons
/// pinned to the bottom.
private struct OnboardingPage<Content: View, Actions: View>: View {
    var symbol: String? = nil
    var tint: Color = .appAccent
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .screenTitle()
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(.appText)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            content
        }
        .scrollContentBackground(.hidden)
        .background(.appBackground)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 14) { actions }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The big full-width button at the bottom of each step.
private struct PrimaryButton: View {
    let title: String
    var busy = false
    let action: () -> Void

    init(_ title: String, busy: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.busy = busy
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(busy ? 0 : 1)
                if busy { ProgressView() }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .allowsHitTesting(!busy)
        .sensoryFeedback(.impact(weight: .light), trigger: busy)
    }
}
