import SwiftData
import SwiftUI

@main
@MainActor
struct SistemaApp: App {
    @State private var environment = AppEnvironment.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment.game)
                .modelContainer(environment.container)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { environment.game.evaluate() }
        }
    }
}

/// Inyección de dependencias: contenedor, reloj y notificaciones.
@MainActor
struct AppEnvironment {
    let container: ModelContainer
    let game: GameService

    nonisolated static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-uitesting") }
    /// Pruebas unitarias alojadas en la app: sin base real ni permisos.
    nonisolated static var isUnitTesting: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
    nonisolated static var isTesting: Bool { isUITesting || isUnitTesting }

    static func make() -> AppEnvironment {
        let container: ModelContainer
        do {
            container = try SistemaSchema.makeContainer(inMemory: isTesting)
        } catch {
            fatalError("No se pudo abrir la base de datos: \(error)")
        }
        let notifications: NotificationScheduling = isTesting ? SilentNotificationService() : LocalNotificationService()
        let game = GameService(context: container.mainContext, clock: SystemDateProvider(), notifications: notifications)
        return AppEnvironment(container: container, game: game)
    }
}
