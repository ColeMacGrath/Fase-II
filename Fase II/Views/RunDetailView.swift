import SwiftUI

/// Resultado de un análisis: resumen, plan con semáforo y ejecución.
struct RunDetailView: View {
    @Environment(AgentStore.self) private var store
    let runID: AgentRun.ID
    @State private var confirmBatch = false

    private var run: AgentRun? { store.runs.first { $0.id == runID } }

    var body: some View {
        if let run {
            Card(title: "Plan propuesto", symbol: "list.bullet.rectangle.portrait") {
                VStack(alignment: .leading, spacing: 16) {
                    summary(run)
                    if run.blocked {
                        blockedBanner(run)
                    } else if run.items.isEmpty {
                        Text("El agente no propuso acciones.").foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(run.items) { item in
                                ActionCard(item: item)
                            }
                        }
                        footer(run)
                    }
                }
            }
            .confirmationDialog(
                "Confirmar \(store.mediumPendingCount) acción(es) de riesgo medio",
                isPresented: $confirmBatch
            ) {
                Button("Ejecutar plan") { Task { await store.executeCurrentPlan() } }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Las acciones de riesgo bajo y medio se ejecutarán ahora. Las de riesgo alto pedirán Touch ID una por una.")
            }
        }
    }

    private func summary(_ run: AgentRun) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SourceBadge(source: run.source)
                if run.blocked {
                    BlockedBadge()
                } else {
                    RiskBadge(level: run.overallRisk)
                }
                Spacer()
                Text(run.date, format: .dateTime.hour().minute().second())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(run.summary)
                .font(.title3.weight(.medium))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                StatChip(symbol: "cpu", text: run.model)
                StatChip(symbol: "stopwatch", text: "\(run.latencyMs) ms")
                StatChip(symbol: "eye.slash", text: "PII local \(run.piiMaskedLocal)")
                StatChip(symbol: "server.rack", text: "PII en servidor \(run.piiMaskedServer)", tint: run.piiMaskedServer == 0 ? .green : .red)
                if run.sentImage { StatChip(symbol: "photo", text: "Captura enmascarada enviada") }
            }
        }
    }

    private func blockedBanner(_ run: AgentRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ejecución cancelada por el validador de inyección", systemImage: "hand.raised.fill")
                .font(.headline).foregroundStyle(.red)
            ForEach(run.blockReasons, id: \.self) { reason in
                Text("• \(reason)").font(.callout)
            }
            Text("Puntaje de inyección: \(run.injectionScore, format: .number.precision(.fractionLength(2)))")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.red.opacity(0.3)))
    }

    private func footer(_ run: AgentRun) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                RiskLegend()
                Spacer()
                if run.isExecuted {
                    Label("Plan procesado", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    Button("Rechazar", role: .destructive) { store.rejectCurrentPlan() }
                        .disabled(store.isExecuting)
                    Button {
                        if store.mediumPendingCount > 0 { confirmBatch = true } else { Task { await store.executeCurrentPlan() } }
                    } label: {
                        if store.isExecuting {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Ejecutando…") }
                        } else {
                            Label("Ejecutar plan", systemImage: "play.fill")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(store.isExecuting || store.currentRunID != run.id)
                }
            }
        }
    }
}

struct ActionCard: View {
    let item: ActionItem
    @State private var expanded = false

    var body: some View {
        let action = item.action
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: action.type.symbol)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(action.risk.color)
                    .background(action.risk.color.opacity(0.12), in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.type.title).font(.caption).foregroundStyle(.secondary)
                    Text(action.description).font(.body.weight(.medium))
                    if !action.target.isEmpty {
                        Text(action.target).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 6) {
                    RiskBadge(level: action.risk, compact: true)
                    Label(item.status.title, systemImage: item.status.symbol)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                }
            }
            if expanded {
                details(action)
            }
        }
        .padding(14)
        .background(.background, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(action.risk.color.opacity(0.25)))
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
    }

    private func details(_ action: PlannedAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Clasificador").foregroundStyle(.secondary)
                    Text("\(action.riskSources["modelo"] ?? "n/a"), confianza \(action.modelConfidence, format: .percent.precision(.fractionLength(0)))")
                }
                GridRow {
                    Text("Reglas").foregroundStyle(.secondary)
                    Text("\(action.riskSources["reglas"] ?? "n/a"), \(action.riskSources["motivo_regla"] ?? "")")
                }
                GridRow {
                    Text("Ejecución").foregroundStyle(.secondary)
                    Text(action.executable ? "Real, en lista blanca" : "Simulada")
                }
            }
            .font(.caption)
            if !action.content.isEmpty {
                Text(action.content)
                    .font(.caption.monospaced())
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: .rect(cornerRadius: 8))
            }
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .pendiente: .secondary
        case .ejecutada: .green
        case .simulada: .blue
        case .rechazada: .secondary
        case .fallida: .orange
        }
    }
}
