import Foundation

/// Dónde se resolvió la tarea: en el equipo o en la Capa Nube.
nonisolated enum RunSource: String, Codable, Sendable {
    case local
    case nube

    var title: String { self == .local ? "Capa Local" : "Capa Nube" }
    var symbol: String { self == .local ? "laptopcomputer" : "cloud" }
}

nonisolated enum ActionStatus: Equatable, Sendable {
    case pendiente
    case ejecutada
    case simulada
    case rechazada
    case fallida(String)

    var title: String {
        switch self {
        case .pendiente: "Pendiente"
        case .ejecutada: "Ejecutada"
        case .simulada: "Simulada tras Touch ID"
        case .rechazada: "Rechazada"
        case .fallida(let reason): "Falló: \(reason)"
        }
    }

    var symbol: String {
        switch self {
        case .pendiente: "circle.dashed"
        case .ejecutada: "checkmark.circle.fill"
        case .simulada: "touchid"
        case .rechazada: "xmark.circle.fill"
        case .fallida: "exclamationmark.triangle.fill"
        }
    }
}

struct ActionItem: Identifiable, Equatable {
    let id = UUID()
    var action: PlannedAction
    var status: ActionStatus = .pendiente

    static func == (lhs: ActionItem, rhs: ActionItem) -> Bool { lhs.id == rhs.id && lhs.status == rhs.status }
}

struct AgentRun: Identifiable {
    let id = UUID()
    let date = Date.now
    var task: String
    var source: RunSource
    var summary: String
    var items: [ActionItem]
    var overallRisk: RiskLevel
    var blocked: Bool
    var blockReasons: [String]
    var latencyMs: Int
    var model: String
    var piiMaskedLocal: Int
    var piiMaskedServer: Int
    var injectionScore: Double
    var sentImage: Bool
    var isExecuted = false

    var pendingCount: Int { items.filter { $0.status == .pendiente }.count }
}
