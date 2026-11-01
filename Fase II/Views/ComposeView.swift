import SwiftUI
import UniformTypeIdentifiers

struct ComposeView: View {
    @Environment(AgentStore.self) private var store
    @State private var showImporter = false
    @State private var showOriginal = false
    @FocusState private var taskFocused: Bool

    private let examples = [
        "Abre tecmilenio.mx",
        "Copia el texto de la pantalla",
        "Extrae la tabla de la captura y guárdala como CSV",
        "Resume el correo y copia los pendientes",
        "Paga la factura que aparece en pantalla",
    ]

    var body: some View {
        @Bindable var store = store
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                screenCard
                taskCard
                if let error = store.errorMessage {
                    ErrorBanner(message: error) { store.errorMessage = nil }
                }
                if let run = store.currentRun {
                    RunDetailView(runID: run.id)
                        .id("plan")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(.smooth, value: store.currentRunID)
        }
        .onChange(of: store.currentRunID) { _, newValue in
            guard newValue != nil else { return }
            withAnimation(.smooth) { proxy.scrollTo("plan", anchor: .top) }
        }
        }
        .navigationTitle("Nueva tarea")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.png, .jpeg, .heic, .tiff]) { result in
            if case .success(let url) = result {
                Task { await store.importImage(at: url) }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Menu("Escenarios", systemImage: "play.rectangle.on.rectangle") {
                    ForEach(DemoScenario.allCases) { scenario in
                        Button(scenario.title) { Task { await store.load(scenario) } }
                    }
                }
                .help("Carga una pantalla de ejemplo y su tarea")
                Button("Capturar pantalla", systemImage: "camera.viewfinder") {
                    Task { await store.captureScreen() }
                }
                .help("Captura la pantalla principal sin incluir esta ventana")
                Button("Importar imagen", systemImage: "photo.on.rectangle.angled") { showImporter = true }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("¿Qué quieres automatizar?")
                .font(.largeTitle.weight(.bold))
            Text("La captura se lee y se enmascara en este equipo. A la Capa Nube solo viaja la versión anonimizada.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Pantalla

    private var screenCard: some View {
        Card(title: "Pantalla", symbol: "rectangle.dashed.and.paperclip") {
            if store.isProcessingScreen {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Reconociendo texto y aplicando el Filtro Ciego…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            } else if let screen = store.screen {
                VStack(alignment: .leading, spacing: 14) {
                    RedactedPreview(screen: screen, showOriginal: showOriginal)
                    HStack(spacing: 10) {
                        StatChip(symbol: "text.viewfinder", text: "\(screen.lineCount) líneas")
                        StatChip(symbol: "eye.slash.fill", text: "\(screen.piiTotal) datos enmascarados", tint: screen.piiTotal > 0 ? .purple : .secondary)
                        StatChip(symbol: "stopwatch", text: "OCR \(screen.ocrMilliseconds) ms")
                        Spacer()
                        Toggle("Ver original", isOn: $showOriginal)
                            .toggleStyle(.switch).controlSize(.small)
                            .help("Solo se muestra aquí. Nunca se envía.")
                        Button("Quitar", systemImage: "xmark.circle") { store.clearScreen() }
                            .buttonStyle(.borderless)
                    }
                    @Bindable var store = store
                    Toggle(isOn: $store.sendImage) {
                        Label("Enviar la captura enmascarada a la Capa Nube", systemImage: "photo.badge.checkmark")
                    }
                    DisclosureGroup("Texto reconocido y enmascarado") {
                        ScrollView {
                            Text(screen.maskedText.isEmpty ? "Sin texto" : screen.maskedText)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                    }
                }
            } else {
                emptyScreen
            }
        }
    }

    private var emptyScreen: some View {
        VStack(spacing: 14) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
            Text("Sin captura").font(.headline)
            Text("Opcional. Captura la pantalla o importa una imagen para darle contexto al agente.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Capturar pantalla", systemImage: "camera.viewfinder") {
                        Task { await store.captureScreen() }
                    }
                    Button("Importar imagen", systemImage: "photo.on.rectangle.angled") { showImporter = true }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await store.importImage(at: url) }
            return true
        }
    }

    // MARK: Tarea

    private var taskCard: some View {
        @Bindable var store = store
        return Card(title: "Tarea", symbol: "text.bubble") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Describe la tarea en lenguaje natural", text: $store.task, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .lineLimit(2...5)
                    .focused($taskFocused)
                    .padding(14)
                    .background(.background.secondary, in: .rect(cornerRadius: 12))
                    .onSubmit { Task { await store.analyze() } }

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(examples, id: \.self) { example in
                            Button(example) { store.task = example }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                        }
                    }
                }
                .scrollIndicators(.hidden)

                HStack {
                    Label("Las tareas simples se resuelven en el equipo. Las demás van a la Capa Nube.", systemImage: "arrow.triangle.branch")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await store.analyze() }
                    } label: {
                        if store.isAnalyzing {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Analizando…") }
                        } else {
                            Label("Analizar", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(store.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isAnalyzing)
                }
            }
        }
    }
}

/// Vista previa de la captura con las zonas tapadas resaltadas.
struct RedactedPreview: View {
    let screen: ScreenAnalysis
    let showOriginal: Bool

    var body: some View {
        let image = showOriginal ? screen.original : screen.redacted
        Image(decorative: image, scale: 1)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ForEach(Array(screen.redactions.enumerated()), id: \.offset) { _, rect in
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(.purple, lineWidth: 2)
                            .background(.purple.opacity(showOriginal ? 0.15 : 0), in: .rect(cornerRadius: 3))
                            .frame(width: rect.width * geo.size.width + 6, height: rect.height * geo.size.height + 6)
                            .position(x: rect.midX * geo.size.width, y: rect.midY * geo.size.height)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            .frame(maxHeight: 360)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    ComposeView()
        .environment(AgentStore())
        .frame(width: 900, height: 800)
}
