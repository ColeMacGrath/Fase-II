import SwiftUI

/// Libro Mayor local con verificación de la cadena de hashes.
struct AuditView: View {
    @Environment(AgentStore.self) private var store
    @State private var selection: AuditLedger.Entry.ID?

    private var ledger: AuditLedger { store.ledger }

    var body: some View {
        VStack(spacing: 0) {
            integrityBar
            Table(ledger.entries.reversed(), selection: $selection) {
                TableColumn("#") { Text("\($0.index)").monospacedDigit() }
                    .width(40)
                TableColumn("Fecha") { Text($0.timestamp, format: .dateTime.day().month().hour().minute().second()) }
                    .width(min: 120, ideal: 140)
                TableColumn("Evento") { Text($0.event).font(.callout.monospaced()) }
                    .width(min: 150, ideal: 190)
                TableColumn("Detalle") { Text($0.detail).lineLimit(2).help($0.detail) }
                TableColumn("Hash") { entry in
                    Text(entry.hash.prefix(12) + "…")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .help("Hash: \(entry.hash)\nAnterior: \(entry.previousHash)")
                }
                .width(110)
            }
            .overlay {
                if ledger.entries.isEmpty {
                    ContentUnavailableView("El Libro Mayor está vacío", systemImage: "checkmark.seal.text.page", description: Text("Cada análisis y cada acción quedan registrados aquí."))
                }
            }
        }
        .navigationTitle("Libro Mayor")
        .toolbar {
            ToolbarItemGroup {
                Menu("Pruebas", systemImage: "testtube.2") {
                    Button("Simular alteración de una entrada") { ledger.simulateTampering() }
                    Button("Recargar desde disco") { ledger.reloadFromDisk() }
                }
                Button("Verificar integridad", systemImage: "checkmark.shield") {
                    withAnimation { _ = ledger.verify() }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private var integrityBar: some View {
        HStack(spacing: 10) {
            switch ledger.integrity {
            case .unknown:
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                Text("Integridad sin verificar · \(ledger.entries.count) entradas")
            case .valid(let count):
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Cadena íntegra: \(count) entradas verificadas con SHA-256")
            case .broken(let index):
                Image(systemName: "xmark.seal.fill").foregroundStyle(.red)
                Text("Cadena rota en la entrada #\(index). El registro fue alterado.")
            }
            Spacer()
            Text("Solo en este equipo · FIFO de \(AuditLedger.maxEntries) entradas")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
