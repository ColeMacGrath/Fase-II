import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case tarea, historial, bitacora, sistema

    var id: Self { self }

    var title: String {
        switch self {
        case .tarea: "Nueva tarea"
        case .historial: "Historial"
        case .bitacora: "Libro Mayor"
        case .sistema: "Sistema y KPIs"
        }
    }

    var symbol: String {
        switch self {
        case .tarea: "wand.and.sparkles"
        case .historial: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .bitacora: "checkmark.seal.text.page"
        case .sistema: "gauge.with.dots.needle.67percent"
        }
    }
}

struct ContentView: View {
    @Environment(AgentStore.self) private var store
    @State private var selection: SidebarItem? = SidebarItem(rawValue: UserDefaults.standard.string(forKey: "initialTab") ?? "") ?? .tarea

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Agente") {
                    ForEach([SidebarItem.tarea, .historial]) { item in
                        Label(item.title, systemImage: item.symbol)
                            .badge(item == .historial ? store.runs.count : 0)
                    }
                }
                Section("Gobernanza") {
                    ForEach([SidebarItem.bitacora, .sistema]) { item in
                        Label(item.title, systemImage: item.symbol)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                BackendStatusPill()
                    .padding(12)
            }
        } detail: {
            switch selection ?? .tarea {
            case .tarea: ComposeView()
            case .historial: HistoryView()
            case .bitacora: AuditView()
            case .sistema: SystemView()
            }
        }
    }
}

/// Indicador del estado de la Capa Nube en la barra lateral.
struct BackendStatusPill: View {
    @Environment(AgentStore.self) private var store

    var body: some View {
        Button {
            Task { await store.refreshHealth() }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.6), radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption.weight(.semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if store.isCheckingHealth {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .help("Toca para volver a comprobar la conexión")
    }

    private var color: Color {
        guard let health = store.health else { return .red }
        return health.claudeMode == "live" ? .green : .orange
    }

    private var title: String { store.health == nil ? "Capa Nube sin conexión" : "Capa Nube conectada" }

    private var subtitle: String {
        guard let health = store.health else { return store.backendURL }
        return health.claudeMode == "live" ? health.claudeModel : "Modo de pruebas determinista"
    }
}

#Preview {
    ContentView()
        .environment(AgentStore())
        .frame(width: 1100, height: 720)
}
