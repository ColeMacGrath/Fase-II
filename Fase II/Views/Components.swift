import SwiftUI

/// Tarjeta base de la interfaz.
struct Card<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary.opacity(0.6), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.separator.opacity(0.6)))
    }
}

struct StatChip: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.1), in: .capsule)
    }
}

/// Insignia del semáforo de riesgo.
struct RiskBadge: View {
    let level: RiskLevel
    var compact = false

    var body: some View {
        Label(compact ? level.rawValue.capitalized : level.title, systemImage: level.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(level.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint(level.color.opacity(0.18)), in: .capsule)
            .help(level.policy)
    }
}

struct BlockedBadge: View {
    var body: some View {
        Label("Bloqueado", systemImage: "hand.raised.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint(Color.red.opacity(0.18)), in: .capsule)
            .help("El validador detectó instrucciones dirigidas al agente y canceló la ejecución")
    }
}

struct SourceBadge: View {
    let source: RunSource

    var body: some View {
        Label(source.title, systemImage: source.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(source == .local ? .teal : .indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint((source == .local ? Color.teal : .indigo).opacity(0.15)), in: .capsule)
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).frame(maxWidth: .infinity, alignment: .leading)
            Button("Cerrar", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(14)
        .background(.orange.opacity(0.1), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.3)))
    }
}

/// Leyenda del semáforo con la política de cada nivel.
struct RiskLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(RiskLevel.allCases, id: \.self) { level in
                HStack(spacing: 6) {
                    Image(systemName: level.symbol).foregroundStyle(level.color)
                    Text(level.policy)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
