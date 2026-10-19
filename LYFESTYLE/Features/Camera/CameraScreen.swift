//
//  CameraScreen.swift
//  LYFESTYL
//
//  The app. A full-bleed camera with the shutter bottom center, account top
//  left, dashboard top right. Snapping freezes the frame and raises the review
//  drawer while the model reads it. Logging or dismissing drops the frame.
//

import AVKit
import PhotosUI
import SwiftData
import SwiftUI

struct CameraScreen: View {
    /// False while onboarding is up, so the camera doesn't ask for access early.
    let isActive: Bool

    @Environment(CameraController.self) private var camera
    @Environment(FoodAnalyzer.self) private var analyzer
    @Environment(HealthService.self) private var health
    @Environment(GoalStore.self) private var goals
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @Query private var recentMeals: [MealEntry]

    /// The meal in progress, from the shutter until log or dismiss. Holds the frame.
    @State private var draft: MealDraft?
    @State private var showDashboard = false
    @State private var showSettings = false
    @State private var photoItem: PhotosPickerItem?
    @State private var focusPoint: CGPoint?
    @State private var toast: String?
    @State private var shutterTaps = 0
    @State private var logs = 0
    /// Counts frames taken, for the shutter flash.
    @State private var frames = 0

    init(isActive: Bool) {
        self.isActive = isActive
        // Enough to cover "today" in any time zone shift; filtered precisely below.
        let since = Date.now.addingTimeInterval(-36 * 3600)
        _recentMeals = Query(filter: #Predicate<MealEntry> { $0.loggedAt >= since })
    }

    private var cameraShouldRun: Bool {
        isActive && scenePhase == .active && !showDashboard && !showSettings
    }

    var body: some View {
        ZStack {
            Color.appMediaBackground.ignoresSafeArea()
            cameraLayer
            if let image = draft?.image {
                DevelopingPhoto(image: image, isDeveloping: draft?.phase == .analyzing)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            ShutterFlash(trigger: frames).ignoresSafeArea()
        }
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { bottomBar }
        .environment(\.colorScheme, .dark) // camera chrome is glass over video
        .statusBarHidden() // like the system Camera, the feed runs edge to edge
        .sheet(item: $draft, onDismiss: { endDraft() }) { draft in
            ReviewDrawer(draft: draft, onLog: { log(draft) }, onDelete: {}, onDismiss: { self.draft = nil })
                .environment(\.colorScheme, .light)
        }
        .sheet(isPresented: $showDashboard) {
            DashboardView()
                .environment(\.colorScheme, .light)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(\.colorScheme, .light)
        }
        .task(id: cameraShouldRun) {
            if cameraShouldRun {
                await camera.start()
                analyzer.refresh()
                analyzer.prewarm()
            } else {
                camera.stop()
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await importPhoto(item) }
        }
        .onCameraCaptureEvent(isEnabled: draft == nil && camera.state == .running) { event in
            if event.phase == .ended { snap() }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterTaps)
        .sensoryFeedback(.success, trigger: logs)
    }

    // MARK: - Layers

    @ViewBuilder
    private var cameraLayer: some View {
        switch camera.state {
        case .running, .idle:
            CameraPreview(session: camera.session) { point, devicePoint in
                camera.focus(at: devicePoint)
                showFocus(at: point)
            }
            .ignoresSafeArea()
            .overlay {
                if let focusPoint {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.appOnMedia, lineWidth: 1.5)
                        .frame(width: 72, height: 72)
                        .position(focusPoint)
                        .transition(.scale(scale: 1.4).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
        case .needsPermission:
            Color.appMediaBackground.ignoresSafeArea()
        case .denied:
            cameraMessage(
                symbol: "camera.fill",
                title: "Camera is off",
                message: "Allow camera access to snap meals. Frames are read on this iPhone and never saved.",
                action: ("Open Settings", { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } })
            )
        case .unavailable:
            cameraMessage(
                symbol: "camera.fill",
                title: "No camera",
                message: "Choose a photo or search for a food instead.",
                action: nil
            )
        }
    }

    private func cameraMessage(symbol: String, title: String, message: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 44))
                .foregroundStyle(.appOnMedia)
            Text(title)
                .blackCaps(.title3, color: .appOnMedia)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appOnMedia.opacity(0.75))
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.glass)
            }
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chrome

    private var topBar: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 16) {
                HStack {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Account and settings")

                    Spacer()
                    caloriesReadout
                    Spacer()

                    Button { showDashboard = true } label: {
                        Image(systemName: "chart.bar.fill")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Dashboard")
                }
            }
            if let toast {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appOnMedia)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .foregroundStyle(.appOnMedia)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .opacity(draft == nil ? 1 : 0)
        .animation(.snappy, value: toast)
    }

    /// Today at a glance, without opening anything.
    private var caloriesReadout: some View {
        let eaten = recentMeals.filter { Calendar.current.isDateInToday($0.loggedAt) }.map(\.nutrition).total.calories
        let left = goals.goals.calories - eaten
        return VStack(spacing: 0) {
            Text(Formatting.calories(abs(left)))
                .font(.headline.weight(.black))
                .contentTransition(.numericText())
            Text(left >= 0 ? "CAL LEFT" : "CAL OVER")
                .font(.caption2.weight(.black))
                .tracking(0.6)
                .opacity(0.75)
        }
        .monospacedDigit()
        .foregroundStyle(.appOnMedia)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy, value: left)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(left >= 0
            ? "\(Formatting.calories(left)) calories left today"
            : "\(Formatting.calories(-left)) calories over today")
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if case .unavailable(let message) = analyzer.status, camera.state == .running {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.appOnMedia)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    .padding(.horizontal, 24)
            }
            GlassEffectContainer(spacing: 24) {
                HStack(spacing: 44) {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Choose a photo")

                    ShutterButton(action: snap)
                        .disabled(camera.state != .running)

                    Button { draft = MealDraft() } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Search for a food")
                }
            }
        }
        .foregroundStyle(.appOnMedia)
        .padding(.bottom, 24)
        .opacity(draft == nil ? 1 : 0)
    }

    // MARK: - Actions

    private func snap() {
        guard draft == nil else { return }
        shutterTaps += 1
        Task {
            guard let image = await camera.snapshot() else { return }
            begin(with: image)
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard draft == nil,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UprightImage.make(from: data) else { return }
        begin(with: image)
    }

    private func begin(with image: CGImage) {
        frames += 1
        let draft = MealDraft(image: image)
        withAnimation(.easeOut(duration: 0.15)) { self.draft = draft }
        draft.analyze(with: analyzer)
    }

    private func log(_ draft: MealDraft) {
        let foods = draft.foods
        guard !foods.isEmpty else { return }
        MealLog(context: context, health: health).log(foods, at: draft.loggedAt)
        logs += 1
        self.draft = nil
        showToast("Logged \(Formatting.calories(foods.nutrition.calories)) cal")
    }

    /// Drop the draft, and with it the frame.
    private func endDraft() {
        draft?.release()
        draft = nil
        analyzer.prewarm()
    }

    private func showFocus(at point: CGPoint) {
        withAnimation(.snappy) { focusPoint = point }
        Task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeOut) { if focusPoint == point { focusPoint = nil } }
        }
    }

    private func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast == text { toast = nil }
        }
    }
}

/// The review sheet with the drawer's detents, and the frame released the
/// moment it closes for any reason.
struct ReviewDrawer: View {
    let draft: MealDraft
    let onLog: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var detent: PresentationDetent = .medium

    var body: some View {
        ReviewSheet(draft: draft, onLog: onLog, onDelete: onDelete, onDismiss: onDismiss, onGoDeeper: { detent = .large })
            .presentationDetents([.medium, .large], selection: $detent)
            .presentationBackground(.appBackground)
            .presentationBackgroundInteraction(.disabled)
            .onChange(of: draft.phase) { _, phase in
                // Search needs room for results and the keyboard.
                if case .search = phase { detent = .large }
            }
            .onAppear {
                if case .search = draft.phase { detent = .large }
            }
            .onDisappear { draft.release() }
    }
}
