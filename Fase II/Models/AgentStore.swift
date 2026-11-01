import CoreGraphics
import Foundation
import Observation

/// Estado de la app y orquestación del flujo Capa Local, Capa Nube y ejecución.
@Observable
final class AgentStore {
    // Configuración
    var backendURL: String { didSet { UserDefaults.standard.set(backendURL, forKey: "backendURL") } }
    var agentToken: String { didSet { UserDefaults.standard.set(agentToken, forKey: "agentToken") } }
    var sendImage: Bool { didSet { UserDefaults.standard.set(sendImage, forKey: "sendImage") } }

    // Estado de la Capa Nube
    var health: HealthResponse?
    var healthError: String?
    var isCheckingHealth = false

    // Tarea en curso
    var task = ""
    var screen: ScreenAnalysis?
    var isProcessingScreen = false
    var isAnalyzing = false
    var isExecuting = false
    var errorMessage: String?
    var currentRunID: AgentRun.ID?

    // Historial y métricas
    var runs: [AgentRun] = []
    let ledger = AuditLedger()

    var localCount: Int { runs.filter { $0.source == .local }.count }
    var cloudCount: Int { runs.filter { $0.source == .nube }.count }
    var blockedCount: Int { runs.filter(\.blocked).count }
    var piiMaskedLocal: Int { runs.reduce(0) { $0 + $1.piiMaskedLocal } }
    var piiMaskedServer: Int { runs.reduce(0) { $0 + $1.piiMaskedServer } }
    var criticalWithoutConfirmation: Int { 0 }
    var criticalConfirmed: Int {
        runs.flatMap(\.items).filter { $0.action.risk == .alto && $0.status == .simulada }.count
    }

    var currentRun: AgentRun? {
        get { runs.first { $0.id == currentRunID } }
        set {
            guard let newValue, let i = runs.firstIndex(where: { $0.id == newValue.id }) else { return }
            runs[i] = newValue
        }
    }

    private var client: AgentAPIClient { AgentAPIClient(baseURL: backendURL, token: agentToken) }

    init() {
        let defaults = UserDefaults.standard
        backendURL = defaults.string(forKey: "backendURL") ?? "http://localhost:8000"
        agentToken = defaults.string(forKey: "agentToken") ?? ""
        sendImage = defaults.object(forKey: "sendImage") as? Bool ?? true
    }

    // MARK: - Capa Nube

    func refreshHealth() async {
        isCheckingHealth = true
        defer { isCheckingHealth = false }
        do {
            health = try await client.health()
            healthError = nil
        } catch {
            health = nil
            healthError = error.localizedDescription
        }
    }

    // MARK: - Capa Local

    func captureScreen() async {
        errorMessage = nil
        do {
            let image = try await ScreenVision.captureMainDisplay()
            await process(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importImage(at url: URL) async {
        errorMessage = nil
        do {
            await process(try ScreenVision.loadImage(from: url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func process(_ image: CGImage) async {
        isProcessingScreen = true
        defer { isProcessingScreen = false }
        do {
            let analysis = try await ScreenVision.analyze(image)
            screen = analysis
            ledger.append("captura_procesada", detail: "\(analysis.lineCount) líneas, \(analysis.piiTotal) datos enmascarados en local, OCR \(analysis.ocrMilliseconds) ms")
        } catch {
            errorMessage = "No se pudo reconocer el texto: \(error.localizedDescription)"
        }
    }

    func clearScreen() { screen = nil }

    // MARK: - Escenarios de demostración

    func load(_ scenario: DemoScenario, analyzeNow: Bool = false) async {
        errorMessage = nil
        currentRunID = nil
        task = scenario.task
        if let image = scenario.loadImage() {
            await process(image)
        } else {
            screen = nil
        }
        if analyzeNow { await analyze() }
    }

    /// Permite abrir la app directo en un escenario con argumentos de arranque,
    /// por ejemplo: -demoScenario pago_factura -demoAnalyze YES
    func runLaunchScenarioIfNeeded() async {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "demoScenario") == "todos" {
            for scenario in DemoScenario.allCases {
                await load(scenario, analyzeNow: true)
            }
        } else if let raw = defaults.string(forKey: "demoScenario"), let scenario = DemoScenario(rawValue: raw) {
            await load(scenario, analyzeNow: defaults.bool(forKey: "demoAnalyze"))
        }
        if defaults.bool(forKey: "demoTamperLedger") { ledger.simulateTampering() }
        if defaults.bool(forKey: "demoVerifyLedger") { ledger.verify() }
    }

    // MARK: - Análisis

    func analyze() async {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnalyzing else { return }
        errorMessage = nil
        isAnalyzing = true
        defer { isAnalyzing = false }

        let maskedTask = BlindFilter.mask(trimmed)
        let screenText = screen?.maskedText ?? ""
        let localPII = maskedTask.total + (screen?.piiTotal ?? 0)
        let started = ContinuousClock.now

        if let actions = LocalRouter.route(task: maskedTask.masked, screenText: screenText) {
            let elapsed = ContinuousClock.now - started
            let run = AgentRun(
                task: maskedTask.masked, source: .local, summary: "Tarea resuelta en el equipo, sin enviar datos a la red.",
                items: actions.map { ActionItem(action: $0) }, overallRisk: actions.map(\.risk).max() ?? .bajo,
                blocked: false, blockReasons: [], latencyMs: Int(elapsed.components.attoseconds / 1_000_000_000_000_000),
                model: "router local", piiMaskedLocal: localPII, piiMaskedServer: 0, injectionScore: 0, sentImage: false
            )
            register(run)
            return
        }

        var imageBase64: String?
        if sendImage, let redacted = screen?.redacted {
            imageBase64 = await ScreenVision.jpegBase64(redacted)
        }
        let request = AnalyzeRequest(task: maskedTask.masked, screenText: screenText, imageBase64: imageBase64, appContext: nil)
        do {
            let response = try await client.analyze(request)
            let run = AgentRun(
                task: maskedTask.masked, source: .nube, summary: response.summary,
                items: response.actions.map { ActionItem(action: $0) }, overallRisk: response.overallRisk,
                blocked: response.blocked, blockReasons: response.blockReasons, latencyMs: response.latencyMs,
                model: response.model, piiMaskedLocal: localPII, piiMaskedServer: response.piiMaskedServer,
                injectionScore: response.injectionScore, sentImage: imageBase64 != nil
            )
            register(run)
            if response.blocked {
                ledger.append("bloqueo_inyeccion", detail: response.blockReasons.joined(separator: "; "))
            }
        } catch {
            errorMessage = error.localizedDescription
            ledger.append("error_capa_nube", detail: error.localizedDescription)
        }
    }

    private func register(_ run: AgentRun) {
        runs.insert(run, at: 0)
        currentRunID = run.id
        ledger.append(
            "analisis_\(run.source.rawValue)",
            detail: "Tarea: \(run.task) | acciones: \(run.items.count) | riesgo: \(run.overallRisk.rawValue) | PII local: \(run.piiMaskedLocal) | PII servidor: \(run.piiMaskedServer) | modelo: \(run.model)"
        )
    }

    // MARK: - Ejecución con semáforo

    var mediumPendingCount: Int {
        currentRun?.items.filter { $0.status == .pendiente && $0.action.risk == .medio }.count ?? 0
    }

    /// Ejecuta el plan. Riesgo bajo y medio se ejecutan tras la confirmación de lote;
    /// riesgo alto exige Touch ID por acción y solo se simula.
    func executeCurrentPlan() async {
        guard var run = currentRun, !run.blocked, !isExecuting else { return }
        isExecuting = true
        defer { isExecuting = false }

        for i in run.items.indices where run.items[i].status == .pendiente {
            let action = run.items[i].action
            if action.risk == .alto || action.requiresBiometric {
                let outcome = await BiometricGate.confirm(reason: "autorizar: \(action.description)")
                switch outcome {
                case .approved(let method):
                    run.items[i].status = .simulada
                    ledger.append("accion_critica_simulada", detail: "\(action.type.rawValue): \(action.description) | confirmada con \(method)")
                case .denied(let reason):
                    run.items[i].status = .rechazada
                    ledger.append("accion_critica_rechazada", detail: "\(action.type.rawValue): \(action.description) | \(reason)")
                }
            } else if action.executable {
                do {
                    try await ActionExecutor.execute(action)
                    run.items[i].status = .ejecutada
                    ledger.append("accion_ejecutada", detail: "\(action.type.rawValue) [\(action.risk.rawValue)]: \(action.description)")
                } catch {
                    run.items[i].status = .fallida(error.localizedDescription)
                    ledger.append("accion_fallida", detail: "\(action.type.rawValue): \(error.localizedDescription)")
                }
            } else {
                run.items[i].status = .simulada
                ledger.append("accion_simulada", detail: "\(action.type.rawValue): \(action.description)")
            }
            currentRun = run
        }
        run.isExecuted = true
        currentRun = run
    }

    func rejectCurrentPlan() {
        guard var run = currentRun else { return }
        for i in run.items.indices where run.items[i].status == .pendiente {
            run.items[i].status = .rechazada
        }
        run.isExecuted = true
        currentRun = run
        ledger.append("plan_rechazado", detail: run.task)
    }
}
