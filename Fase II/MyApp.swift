import SwiftUI

@main
struct AgenteOSApp: App {
    @State private var store = AgentStore()

    var body: some Scene {
        WindowGroup("Agente OS") {
            ContentView()
                .environment(store)
                .environment(\.locale, Locale(identifier: "es_MX"))
                .frame(minWidth: 1040, minHeight: 680)
                .task {
                    await store.refreshHealth()
                    await store.runLaunchScenarioIfNeeded()
                }
        }
        .defaultSize(width: 1320, height: 1000)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Capturar pantalla") { Task { await store.captureScreen() } }
                    .keyboardShortcut("2", modifiers: [.command, .shift])
                Button("Analizar tarea") { Task { await store.analyze() } }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            CommandMenu("Demo") {
                ForEach(DemoScenario.allCases) { scenario in
                    Button(scenario.title) { Task { await store.load(scenario) } }
                }
            }
        }
    }
}
