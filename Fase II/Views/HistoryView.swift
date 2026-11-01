import SwiftUI

struct HistoryView: View {
    @Environment(AgentStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.runs.isEmpty {
                    ContentUnavailableView("Sin tareas todavía", systemImage: "tray", description: Text("Las tareas analizadas en esta sesión aparecerán aquí."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.runs) { run in
                                NavigationLink(value: run.id) {
                                    HistoryRow(run: run)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 980)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Historial")
            .navigationDestination(for: AgentRun.ID.self) { id in
                ScrollView {
                    RunDetailView(runID: id)
                        .padding(28)
                        .frame(maxWidth: 980)
                        .frame(maxWidth: .infinity)
                }
                .onAppear { store.currentRunID = id }
            }
        }
    }
}

private struct HistoryRow: View {
    let run: AgentRun

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: run.blocked ? "hand.raised.fill" : run.source.symbol)
                .font(.title3)
                .foregroundStyle(run.blocked ? .red : (run.source == .local ? .teal : .indigo))
                .frame(width: 40, height: 40)
                .background((run.blocked ? Color.red : (run.source == .local ? .teal : .indigo)).opacity(0.12), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(run.task).font(.body.weight(.medium)).lineLimit(1)
                Text("\(run.source.title) · \(run.items.count) acción(es) · \(run.latencyMs) ms · \(run.model)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if run.blocked { BlockedBadge() } else { RiskBadge(level: run.overallRisk, compact: true) }
            Text(run.date, format: .dateTime.hour().minute())
                .font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background.secondary.opacity(0.6), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.6)))
        .contentShape(.rect)
    }
}
