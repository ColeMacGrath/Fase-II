import Charts
import SwiftUI

/// Estado de la Capa Nube, configuración y KPIs de la compuerta de Fase I.
struct SystemView: View {
    @Environment(AgentStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sistema y KPIs").font(.largeTitle.weight(.bold))

                Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                    GridRow {
                        KPITile(title: "Resueltas en local", value: "\(store.localCount)", detail: share(store.localCount), symbol: "laptopcomputer", tint: .teal)
                        KPITile(title: "Enviadas a la nube", value: "\(store.cloudCount)", detail: share(store.cloudCount), symbol: "cloud", tint: .indigo)
                        KPITile(title: "Bloqueos por inyección", value: "\(store.blockedCount)", detail: "Validador R01", symbol: "hand.raised", tint: .red)
                    }
                    GridRow {
                        KPITile(title: "PII enmascarada en local", value: "\(store.piiMaskedLocal)", detail: "Filtro Ciego", symbol: "eye.slash", tint: .purple)
                        KPITile(title: "PII que llegó al servidor", value: "\(store.piiMaskedServer)", detail: "Meta de Fase I: 0", symbol: "server.rack", tint: store.piiMaskedServer == 0 ? .green : .red)
                        KPITile(title: "Críticas sin confirmación", value: "\(store.criticalWithoutConfirmation)", detail: "\(store.criticalConfirmed) confirmadas con Touch ID", symbol: "touchid", tint: .green)
                    }
                }

                Card(title: "Distribución local y nube", symbol: "chart.pie") {
                    if store.runs.isEmpty {
                        Text("Aún no hay tareas en esta sesión.").foregroundStyle(.secondary)
                    } else {
                        Chart {
                            SectorMark(angle: .value("Tareas", store.localCount), innerRadius: .ratio(0.6), angularInset: 2)
                                .foregroundStyle(by: .value("Capa", "Local"))
                            SectorMark(angle: .value("Tareas", store.cloudCount), innerRadius: .ratio(0.6), angularInset: 2)
                                .foregroundStyle(by: .value("Capa", "Nube"))
                        }
                        .chartForegroundStyleScale(["Local": Color.teal, "Nube": Color.indigo])
                        .frame(height: 180)
                    }
                }

                Card(title: "Capa Nube", symbol: "server.rack") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            TextField("URL del backend", text: $store.backendURL)
                                .textFieldStyle(.roundedBorder)
                            SecureField("Token de agente, opcional", text: $store.agentToken)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                            Button("Probar conexión", systemImage: "bolt.horizontal") {
                                Task { await store.refreshHealth() }
                            }
                        }
                        if let health = store.health {
                            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                                row("Servicio", "\(health.service) \(health.version)")
                                row("Modo de Claude", health.claudeMode == "live" ? "Live" : "Pruebas, planificador determinista")
                                row("Modelo", health.claudeModel)
                                row("Clasificador de riesgo", health.riskModelVersion)
                                row("Token requerido", health.authRequired ? "Sí" : "No")
                            }
                            if !health.riskModelMetrics.isEmpty {
                                HStack(spacing: 8) {
                                    ForEach(health.riskModelMetrics.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                        StatChip(symbol: "chart.bar", text: "\(key) \(value.formatted(.number.precision(.fractionLength(2))))")
                                    }
                                }
                            }
                        } else if let error = store.healthError {
                            ErrorBanner(message: error) { store.healthError = nil }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Sistema")
    }

    private func share(_ count: Int) -> String {
        let total = store.runs.count
        guard total > 0 else { return "Sin datos" }
        return (Double(count) / Double(total)).formatted(.percent.precision(.fractionLength(0))) + " del total"
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

struct KPITile: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.08)), in: .rect(cornerRadius: 16))
    }
}
