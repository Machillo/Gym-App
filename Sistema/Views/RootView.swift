import SwiftData
import SwiftUI

@MainActor
struct RootView: View {
    @Environment(GameService.self) private var game
    @Query private var players: [Player]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if players.isEmpty {
                OnboardingView()
            } else {
                MainTabView()
            }
            SystemAnnouncementOverlay()
        }
        .task {
            #if DEBUG
            if let xp = AppEnvironment.priorHistoryXPArgument { game.applyPriorHistory(xp: xp) }
            if let program = AppEnvironment.adoptProgramArgument { game.adoptProgram(named: program) }
            if let history = AppEnvironment.bodyHistoryArgument { game.importBodyHistory(history) }
            #endif
            game.evaluate()
            if !AppEnvironment.isTesting {
                game.notifications.requestAuthorization()
                game.runAutoBackupIfDue()
                await game.syncHealth()
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { StatusView() }
                .tabItem { Label("Estado", systemImage: "person.crop.square.filled.and.at.rectangle") }
            NavigationStack { TrainingHubView() }
                .tabItem { Label("Entrenar", systemImage: "dumbbell") }
            NavigationStack { ProgressScreen() }
                .tabItem { Label("Progreso", systemImage: "chart.xyaxis.line") }
            NavigationStack { TrialsView() }
                .tabItem { Label("Pruebas", systemImage: "shield.lefthalf.filled") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
        }
    }
}

/// Mensajes animados del Sistema al subir/bajar de nivel, división o rango.
@MainActor
struct SystemAnnouncementOverlay: View {
    @Environment(GameService.self) private var game
    @State private var appeared = false

    var body: some View {
        if let current = game.announcements.first {
            let tint = current.positive ? Theme.glow : Theme.danger
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("EL SISTEMA")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.secondaryText)
                    Text(current.headline)
                        .font(Theme.display(34, weight: .black))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(tint)
                    Text(current.message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text("Tocá para continuar")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .systemPanel(tint: tint)
                .padding(32)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            }
            .id(current.id)
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .onAppear {
                appeared = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appeared = true }
            }
            .task(id: current.id) {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if game.announcements.first?.id == current.id { dismiss() }
            }
            .accessibilityIdentifier("announcement")
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.2)) { appeared = false }
        game.dismissAnnouncement()
    }
}
