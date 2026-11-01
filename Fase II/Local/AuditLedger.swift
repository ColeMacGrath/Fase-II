import CryptoKit
import Foundation
import Observation

/// Libro Mayor de auditoría local con hashes SHA-256 encadenados.
///
/// Cada entrada incluye el hash de la anterior, así que modificar o borrar una
/// entrada rompe la cadena y la verificación lo detecta. Se guarda solo en el
/// equipo, dentro del contenedor de la app, con un tope de entradas FIFO.
@Observable
final class AuditLedger {
    struct Entry: Codable, Identifiable, Hashable {
        var id: Int { index }
        let index: Int
        let timestamp: Date
        let event: String
        var detail: String
        let previousHash: String
        let hash: String
    }

    enum Integrity: Equatable {
        case unknown
        case valid(count: Int)
        case broken(atIndex: Int)
    }

    static let genesisHash = String(repeating: "0", count: 64)
    static let maxEntries = 5_000

    private(set) var entries: [Entry] = []
    private(set) var integrity: Integrity = .unknown
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = URL.applicationSupportDirectory.appending(path: "AgenteOS", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            self.fileURL = support.appending(path: "libro_mayor.json")
        }
        load()
    }

    static func computeHash(index: Int, timestamp: Date, event: String, detail: String, previousHash: String) -> String {
        let payload = "\(index)|\(timestamp.timeIntervalSince1970)|\(event)|\(detail)|\(previousHash)"
        return SHA256.hash(data: Data(payload.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func append(_ event: String, detail: String) -> Entry {
        let index = (entries.last?.index ?? -1) + 1
        let previous = entries.last?.hash ?? Self.genesisHash
        let now = Date.now
        let hash = Self.computeHash(index: index, timestamp: now, event: event, detail: detail, previousHash: previous)
        let entry = Entry(index: index, timestamp: now, event: event, detail: detail, previousHash: previous, hash: hash)
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        integrity = .unknown
        save()
        return entry
    }

    @discardableResult
    func verify() -> Integrity {
        for (offset, entry) in entries.enumerated() {
            let expected = Self.computeHash(index: entry.index, timestamp: entry.timestamp, event: entry.event, detail: entry.detail, previousHash: entry.previousHash)
            let linked = offset == 0 || entries[offset - 1].hash == entry.previousHash
            if expected != entry.hash || !linked {
                integrity = .broken(atIndex: entry.index)
                return integrity
            }
        }
        integrity = .valid(count: entries.count)
        return integrity
    }

    /// Altera una entrada en memoria para demostrar que la verificación detecta el cambio.
    /// No se guarda en disco.
    func simulateTampering() {
        guard let i = entries.indices.dropLast().last ?? entries.indices.last else { return }
        entries[i].detail += " [modificado]"
        integrity = .unknown
    }

    func reloadFromDisk() {
        load()
        integrity = .unknown
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        entries = (try? decoder.decode([Entry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
