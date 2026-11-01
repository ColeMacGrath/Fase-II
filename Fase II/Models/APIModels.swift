import Foundation
import SwiftUI

// MARK: - Semáforo de riesgo

nonisolated enum RiskLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case bajo, medio, alto

    var rank: Int {
        switch self {
        case .bajo: 0
        case .medio: 1
        case .alto: 2
        }
    }

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rank < rhs.rank }

    var title: String {
        switch self {
        case .bajo: "Riesgo bajo"
        case .medio: "Riesgo medio"
        case .alto: "Riesgo alto"
        }
    }

    var policy: String {
        switch self {
        case .bajo: "Se ejecuta sin confirmación"
        case .medio: "Se confirma en lote"
        case .alto: "Requiere Touch ID y se simula"
        }
    }

    var color: Color {
        switch self {
        case .bajo: .green
        case .medio: .orange
        case .alto: .red
        }
    }

    var symbol: String {
        switch self {
        case .bajo: "checkmark.shield.fill"
        case .medio: "exclamationmark.shield.fill"
        case .alto: "lock.shield.fill"
        }
    }
}

// MARK: - Tipos de acción

nonisolated enum ActionType: String, Codable, CaseIterable, Sendable {
    case openURL = "open_url"
    case openApp = "open_app"
    case copyToClipboard = "copy_to_clipboard"
    case saveTextFile = "save_text_file"
    case deleteFile = "delete_file"
    case sendMessage = "send_message"
    case payment
    case modifyRecord = "modify_record"
    case runCommand = "run_command"
    case other

    var title: String {
        switch self {
        case .openURL: "Abrir enlace"
        case .openApp: "Abrir app"
        case .copyToClipboard: "Copiar"
        case .saveTextFile: "Guardar archivo"
        case .deleteFile: "Eliminar"
        case .sendMessage: "Enviar mensaje"
        case .payment: "Pago"
        case .modifyRecord: "Modificar registro"
        case .runCommand: "Ejecutar comando"
        case .other: "Paso manual"
        }
    }

    var symbol: String {
        switch self {
        case .openURL: "safari"
        case .openApp: "app.badge"
        case .copyToClipboard: "doc.on.clipboard"
        case .saveTextFile: "square.and.arrow.down"
        case .deleteFile: "trash"
        case .sendMessage: "paperplane"
        case .payment: "creditcard"
        case .modifyRecord: "cylinder.split.1x2"
        case .runCommand: "terminal"
        case .other: "hand.point.up.left"
        }
    }
}

// MARK: - Contratos de la API

nonisolated struct PlannedAction: Codable, Hashable, Sendable {
    var type: ActionType
    var description: String
    var target: String
    var content: String
    var risk: RiskLevel
    var riskSources: [String: String]
    var modelConfidence: Double
    var executable: Bool
    var requiresBiometric: Bool
    var simulated: Bool
}

nonisolated struct AnalyzeRequest: Encodable, Sendable {
    var task: String
    var screenText: String
    var imageBase64: String?
    var appContext: String?
}

nonisolated struct AnalyzeResponse: Decodable, Sendable {
    var requestId: String
    var summary: String
    var actions: [PlannedAction]
    var overallRisk: RiskLevel
    var blocked: Bool
    var blockReasons: [String]
    var piiMaskedServer: Int
    var injectionScore: Double
    var claudeMode: String
    var model: String
    var latencyMs: Int
}

nonisolated struct HealthResponse: Decodable, Sendable, Equatable {
    var status: String
    var service: String
    var version: String
    var claudeMode: String
    var claudeModel: String
    var riskModelVersion: String
    var riskModelMetrics: [String: Double]
    var authRequired: Bool
}

nonisolated struct APIErrorBody: Decodable, Sendable {
    var detail: String
}
