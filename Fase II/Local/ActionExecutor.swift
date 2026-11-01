import AppKit
import UniformTypeIdentifiers

/// Ejecuta las acciones de la lista blanca. Nada fuera de esta lista se ejecuta.
enum ActionExecutor {
    enum ExecutionError: LocalizedError {
        case invalidURL
        case appNotFound(String)
        case cancelled
        case notExecutable

        var errorDescription: String? {
            switch self {
            case .invalidURL: "URL no válida o no segura"
            case .appNotFound(let name): "No encontré la app \(name)"
            case .cancelled: "Cancelado"
            case .notExecutable: "Acción fuera de la lista blanca"
            }
        }
    }

    static func execute(_ action: PlannedAction) async throws {
        switch action.type {
        case .openURL:
            guard let url = URL(string: action.target), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme) else {
                throw ExecutionError.invalidURL
            }
            NSWorkspace.shared.open(url)

        case .openApp:
            let url = try locateApp(named: action.target)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)

        case .copyToClipboard:
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(action.content, forType: .string)

        case .saveTextFile:
            let panel = NSSavePanel()
            panel.nameFieldStringValue = action.target.isEmpty ? "resultado.txt" : action.target
            panel.allowedContentTypes = [.plainText]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { throw ExecutionError.cancelled }
            try action.content.write(to: url, atomically: true, encoding: .utf8)

        default:
            throw ExecutionError.notExecutable
        }
    }

    private static func locateApp(named name: String) throws -> URL {
        let clean = name.replacingOccurrences(of: ".app", with: "")
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities"]
        for folder in folders {
            let url = URL(filePath: folder).appending(path: "\(clean).app")
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }
        }
        let bundleGuess = "com.apple.\(clean.replacingOccurrences(of: " ", with: ""))"
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleGuess) { return url }
        throw ExecutionError.appNotFound(clean)
    }
}
