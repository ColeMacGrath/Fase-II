import Foundation

/// Decide si una tarea se resuelve en el equipo o necesita la Capa Nube.
///
/// Fase I plantea que la mayoría de las tareas se resuelvan en local. En la demo,
/// las órdenes directas y sin ambigüedad se atienden aquí sin enviar nada a la red.
nonisolated enum LocalRouter {

    private static let appAliases: [String: String] = [
        "notas": "Notes", "calendario": "Calendar", "mapas": "Maps", "fotos": "Photos",
        "música": "Music", "musica": "Music", "recordatorios": "Reminders", "calculadora": "Calculator",
        "correo": "Mail", "mensajes": "Messages", "contactos": "Contacts", "vista previa": "Preview",
        "configuración": "System Settings", "configuracion": "System Settings", "terminal": "Terminal",
    ]

    static func route(task: String, screenText: String) -> [PlannedAction]? {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if let m = lower.wholeMatch(of: #/(?:abre|abrir|open|ve a|ir a)\s+(https?:\/\/\S+|[\w.-]+\.(?:com|mx|org|net|edu|io|dev)\S*)/#) {
            let raw = String(m.1)
            let url = raw.hasPrefix("http") ? raw : "https://\(raw)"
            return [local(.openURL, "Abrir \(url)", target: url)]
        }

        if let m = lower.wholeMatch(of: #/(?:abre|abrir|open)\s+(?:la app\s+|la aplicación\s+|la aplicacion\s+)?([\p{L} ]{2,30})/#) {
            let name = String(m.1).trimmingCharacters(in: .whitespaces)
            let words = name.split(separator: " ")
            let connectors: Set<Substring> = ["y", "and", "e", "luego", "para", "con", "de"]
            if words.count <= 3, words.allSatisfy({ !connectors.contains($0) }) {
                let appName = appAliases[name] ?? name.capitalized
                return [local(.openApp, "Abrir \(appName)", target: appName)]
            }
        }

        let copyPattern = #/(?:copia|copiar|copy)\s+(?:todo\s+)?(?:el\s+)?(?:texto|contenido)(?:\s+de\s+(?:la\s+)?(?:pantalla|captura|imagen))?/#
        if lower.wholeMatch(of: copyPattern) != nil, !screenText.isEmpty {
            return [local(.copyToClipboard, "Copiar el texto reconocido, ya enmascarado", content: screenText)]
        }

        let savePattern = #/(?:guarda|guardar|save)\s+(?:el\s+)?(?:texto|contenido)(?:\s+de\s+(?:la\s+)?(?:pantalla|captura|imagen))?/#
        if lower.wholeMatch(of: savePattern) != nil, !screenText.isEmpty {
            return [local(.saveTextFile, "Guardar el texto reconocido en un archivo", target: "texto_pantalla.txt", content: screenText, risk: .medio)]
        }
        return nil
    }

    private static func local(_ type: ActionType, _ description: String, target: String = "", content: String = "", risk: RiskLevel = .bajo) -> PlannedAction {
        PlannedAction(
            type: type, description: description, target: target, content: content, risk: risk,
            riskSources: ["reglas": risk.rawValue, "motivo_regla": "router local"], modelConfidence: 1,
            executable: true, requiresBiometric: false, simulated: false
        )
    }
}
